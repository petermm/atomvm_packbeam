%%
%% Copyright (c) 2023 dushin.net
%% All rights reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

-module(prop_packbeam).
-include_lib("proper/include/proper.hrl").

-define(BUILD_DIR, "_build/").
-define(TEST_BEAM_DIR, "_build/test/lib/atomvm_packbeam/test/").

%%
%% Call graph for modules a-f, x
%%
%%
%%          calls                   calls
%%      a (start) ----------> b (start) ---------> e
%%                            |
%%                            | calls (via atomic module name)
%%                            |
%%                            v
%%                            c -----------------> f
%%                              calls (via atom inside of literal)
%%
%%
%%      d  no one calls d :(
%%
%%
%%   x (start) ---> a (start)
%%

%%
%% Properties
%%

prop_simple_test() ->
    ?FORALL(
        ModulePaths,
        module_paths(),
        begin
            Modules = [Module || {Module, _Path} <- ModulePaths],
            Paths = [Path || {_Module, Path} <- ModulePaths],
            AVMFile = dest_dir("prop_simple_test.avm"),
            collect(
                Modules,
                begin
                    ok = packbeam_api:create(AVMFile, Paths),
                    ParsedFiles = packbeam_api:list(AVMFile),
                    modules_and_parsed_files_are_equivalent(Modules, ParsedFiles) andalso
                        all_beam_modules_are_properly_named(ParsedFiles) andalso
                        maybe_contains_start_beam(Modules, a, ParsedFiles) andalso
                        maybe_contains_start_beam(Modules, b, ParsedFiles)
                end
            )
        end
    ).

prop_labt_offsets() ->
    ?FORALL(
        {Instructions, CutFraction},
        {?LET(N, choose(1, 40), vector(N, labt_instruction())), choose(0, 1000)},
        begin
            %% Expected positions come from the generator's encoding lengths,
            %% never from reading back the generated instruction stream.
            {Parts, Offsets, End} = lists:foldl(
                fun({Instruction, Length}, {Acc, Positions, Pos}) ->
                    Id = length(Positions) + 1,
                    {Label, LabelLength} =
                        case Id < 16 of
                            true -> {<<1, (Id bsl 4)>>, 2};
                            false -> {<<1, 8, Id>>, 3}
                        end,
                    {
                        [[Label, Instruction] | Acc],
                        [Pos + LabelLength | Positions],
                        Pos + LabelLength + Length
                    }
                end,
                {[], [], 0},
                Instructions
            ),
            Code = iolist_to_binary([lists:reverse(Parts), 3]),
            Count = length(Offsets) + 1,
            Payload = <<16:32, 0:32, 191:32, Count:32, 1:32, Code/binary>>,
            MakeBeam = fun(C) ->
                beam_lib:build_module([
                    {"AtU8", <<1:32, 4, "labt">>}, {"Code", C}
                ])
            end,
            {ok, Beam} = MakeBeam(Payload),
            Cut = CutFraction * (byte_size(Code) - 1) div 1000,
            Prefix = binary:part(Code, 0, Cut),
            {ok, Truncated} = MakeBeam(<<16:32, 0:32, 191:32, Count:32, 1:32, Prefix/binary>>),
            {error, _} = packbeam_labt:add(Truncated, 32),
            lists:all(
                fun({Width, Bits, Flag}) ->
                    {ok, Packed} = packbeam_labt:add(Beam, Width),
                    {ok, _, Chunks} = beam_lib:all_chunks(Packed),
                    Entries = <<<<Offset:Bits/little>> || Offset <- [0 | lists:reverse(Offsets)]>>,
                    proplists:get_value("Code", Chunks) =:= Payload andalso
                        proplists:get_value("avmL", Chunks) =:=
                            <<End:32/little, Flag:16/little, Count:16/little, Entries/binary>>
                end,
                [{32, 32, 1}, {auto, 16, 0}]
            )
        end
    ).

labt_instruction() ->
    oneof([
        ?LET({Source, Length}, labt_source(), {<<64, Source/binary, 3>>, Length + 2}),
        ?LET(
            Sources,
            resize(30, list(labt_source())),
            begin
                N = length(Sources),
                Values = iolist_to_binary([Bin || {Bin, _} <- Sources]),
                Length = lists:sum([Size || {_, Size} <- Sources]),
                EncodedN =
                    case N < 16 of
                        true -> <<(N bsl 4)>>;
                        false -> <<8, N>>
                    end,
                CountLength =
                    case N < 16 of
                        true -> 1;
                        false -> 2
                    end,
                {<<164, 3, 23, EncodedN/binary, Values/binary>>, 3 + CountLength + Length}
            end
        ),
        {<<16, 55, 32, 0, 16, 16, 32, 0>>, 8}
    ]).

labt_source() ->
    oneof([
        ?LET(Value, choose(0, 15), {<<((Value bsl 4) bor 1)>>, 1}),
        ?LET(
            Value,
            choose(16, 2047),
            {<<(((Value bsr 8) bsl 5) bor 9), (Value band 255)>>, 2}
        ),
        ?LET(Bytes, binary(9), {<<249, 0, Bytes/binary>>, 11}),
        ?LET(Register, choose(0, 15), {<<87, ((Register bsl 4) bor 3), 0>>, 3}),
        ?LET(Index, choose(0, 15), {<<71, (Index bsl 4)>>, 2})
    ]).

modules_and_parsed_files_are_equivalent(Modules, ParsedFiles) ->
    lists:sort(Modules) =:=
        lists:sort([get_module(ParsedFile) || ParsedFile <- get_beam_files(ParsedFiles)]).

all_beam_modules_are_properly_named(ParsedFiles) ->
    lists:all(
        fun(ParsedFile) ->
            Module = get_module(ParsedFile),
            get_module_name(ParsedFile) =:= (atom_to_list(Module) ++ ".beam")
        end,
        get_beam_files(ParsedFiles)
    ).

get_beam_files(ParsedFiles) ->
    [ParsedFile || ParsedFile <- ParsedFiles, is_beam(ParsedFile)].

maybe_contains_start_beam(Modules, Module, ParsedFiles) ->
    case lists:member(Module, Modules) of
        true ->
            is_start(find_parsed_file(Module, ParsedFiles));
        _ ->
            %% ignore
            true
    end.

find_parsed_file(Module, []) ->
    {parsed_file_not_found, Module};
find_parsed_file(Module, [ParsedFile | Rest]) ->
    case get_module(ParsedFile) of
        M when M =:= Module ->
            ParsedFile;
        _ ->
            find_parsed_file(Module, Rest)
    end.
%%
%% Helpers
%%

test_beam_path(Module) ->
    ?TEST_BEAM_DIR ++ atom_to_list(Module) ++ ".beam".

dest_dir(AVMFile) ->
    ?BUILD_DIR ++ AVMFile.

get_module(ParsedFile) ->
    packbeam_api:get_element_module(ParsedFile).

get_module_name(ParsedFile) ->
    packbeam_api:get_element_name(ParsedFile).

is_start(ParsedFile) ->
    packbeam_api:is_entrypoint(ParsedFile).

is_beam(ParsedFile) ->
    packbeam_api:is_beam(ParsedFile).

%%
%% Generators
%%

module_paths() ->
    ?LET(
        Modules,
        list(oneof([a, b, c, d, e, f])),
        remove_duplicates([{Module, test_beam_path(Module)} || Module <- Modules])
    ).

remove_duplicates([]) ->
    [];
remove_duplicates([H | T]) ->
    [H | [X || X <- remove_duplicates(T), X /= H]].
