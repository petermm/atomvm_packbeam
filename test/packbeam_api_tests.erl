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

-module(packbeam_api_tests).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(BUILD_DIR, "_build/").
-define(TEST_BEAM_DIR, "_build/test/lib/atomvm_packbeam/test/").

packbeam_create_simple_test() ->
    AVMFile = dest_dir("packbeam_create_simple_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile, [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                "test/priv/test.txt"
            ]
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),
    ?assertEqual(length(ParsedFiles), 5),

    [AFile, BFile, CFile, DFile, TextFile] = ParsedFiles,

    % io:format(user, "~p~n", [ParsedFiles]),

    ?assertMatch(a, get_module(AFile)),
    ?assertMatch("a.beam", get_module_name(AFile)),
    ?assert(is_beam(AFile)),
    ?assert(is_start(AFile)),
    ?assert(lists:member({start, 0}, get_exports(AFile))),

    ?assertMatch(b, get_module(BFile)),
    ?assertMatch("b.beam", get_module_name(BFile)),
    ?assert(is_beam(BFile)),
    ?assert(is_start(BFile)),
    ?assert(lists:member({start, 0}, get_exports(BFile))),

    ?assertMatch(c, get_module(CFile)),
    ?assertMatch("c.beam", get_module_name(CFile)),
    ?assert(is_beam(CFile)),
    ?assertNot(is_start(CFile)),
    ?assertNot(lists:member({start, 0}, get_exports(CFile))),

    ?assertMatch(d, get_module(DFile)),
    ?assertMatch("d.beam", get_module_name(DFile)),
    ?assert(is_beam(DFile)),
    ?assertNot(is_start(DFile)),
    ?assertNot(lists:member({start, 0}, get_exports(DFile))),

    ?assertNot(is_beam(TextFile)),
    ?assertMatch("test/priv/test.txt", get_module_name(TextFile)),

    ok.

packbeam_create_start_test() ->
    AVMFile = dest_dir("packbeam_create_start_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                "test/priv/test.txt"
            ],
            false,
            b
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),
    ?assertEqual(length(ParsedFiles), 5),

    [BFile | _] = ParsedFiles,

    % io:format(user, "~p~n", [ParsedFiles]),

    ?assertMatch(b, get_module(BFile)),
    ?assertMatch("b.beam", get_module_name(BFile)),
    ?assert(is_beam(BFile)),
    ?assert(is_start(BFile)),
    ?assert(lists:member({start, 0}, get_exports(BFile))),

    ok.

packbeam_create_start_main_test() ->
    AVMFile = dest_dir("packbeam_create_start_main_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("c.beam"),
                test_beam_path("f.beam"),
                test_beam_path("g.beam")
            ],
            false,
            g
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),
    ?assertEqual(length(ParsedFiles), 3),

    [GFile | _] = ParsedFiles,

    % io:format(user, "~p~n", [ParsedFiles]),

    ?assertMatch(g, get_module(GFile)),
    ?assertMatch("g.beam", get_module_name(GFile)),
    ?assert(is_beam(GFile)),
    ?assert(is_start(GFile)),
    ?assert(lists:member({main, 1}, get_exports(GFile))),
    ?assert(not lists:member({start, 0}, get_exports(GFile))),

    ok.

packbeam_create_lib_test() ->
    AVMFile = dest_dir("packbeam_create_lib_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("c.beam"),
                test_beam_path("f.beam"),
                test_beam_path("g.beam")
            ],
            #{
                lib => true
            }
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),
    ?assertEqual(length(ParsedFiles), 3),

    [CFile, FFile, GFile] = ParsedFiles,

    % io:format(user, "~p~n", [ParsedFiles]),

    ?assertMatch(g, get_module(GFile)),
    ?assertMatch("g.beam", get_module_name(GFile)),
    ?assert(is_beam(GFile)),
    ?assertNot(is_start(CFile)),
    ?assertNot(is_start(FFile)),
    ?assertNot(is_start(GFile)),
    ?assert(lists:member({main, 1}, get_exports(GFile))),
    ?assertNot(lists:member({start, 0}, get_exports(GFile))),

    ok.

packbeam_create_lib_from_avm_test() ->
    AVMFile0 = dest_dir("packbeam_create_start_main_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile0,
            [
                test_beam_path("c.beam"),
                test_beam_path("f.beam"),
                test_beam_path("g.beam")
            ],
            false,
            g
        )
    ),

    AVMFile = dest_dir("packbeam_create_lib_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("a.beam"),
                AVMFile0
            ],
            #{
                lib => true
            }
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),
    ?assertEqual(length(ParsedFiles), 4),

    % g was written first in AVMFile0
    [AFile, GFile, CFile, FFile] = ParsedFiles,

    % io:format(user, "~p~n", [ParsedFiles]),

    ?assertMatch(g, get_module(GFile)),
    ?assertMatch("g.beam", get_module_name(GFile)),
    ?assert(is_beam(GFile)),
    ?assertNot(is_start(AFile)),
    ?assertNot(is_start(GFile)),
    ?assertNot(is_start(CFile)),
    ?assertNot(is_start(FFile)),
    ?assert(lists:member({main, 1}, get_exports(GFile))),
    ?assertNot(lists:member({start, 0}, get_exports(GFile))),

    ok.

packbeam_create_prune_test() ->
    AVMFile = dest_dir("packbeam_create_prune_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                test_beam_path("e.beam"),
                test_beam_path("f.beam"),
                "test/priv/test.txt"
            ],
            true,
            b
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),
    ?assertEqual(length(ParsedFiles), 5),

    [BFile, CFile, EFile, FFile, TextFile] = ParsedFiles,

    % io:format(user, "~p~n", [ParsedFiles]),

    ?assertMatch(b, get_module(BFile)),
    ?assertMatch("b.beam", get_module_name(BFile)),
    ?assert(is_beam(BFile)),
    ?assert(is_start(BFile)),
    ?assert(lists:member({start, 0}, get_exports(BFile))),

    ?assertMatch(c, get_module(CFile)),
    ?assertMatch("c.beam", get_module_name(CFile)),
    ?assert(is_beam(CFile)),
    ?assertNot(is_start(CFile)),
    ?assertNot(lists:member({start, 0}, get_exports(CFile))),

    ?assertMatch(e, get_module(EFile)),
    ?assertMatch("e.beam", get_module_name(EFile)),
    ?assert(is_beam(EFile)),
    ?assertNot(is_start(EFile)),
    ?assertNot(lists:member({start, 0}, get_exports(EFile))),

    ?assertMatch(f, get_module(FFile)),
    ?assertMatch("f.beam", get_module_name(FFile)),
    ?assert(is_beam(FFile)),
    ?assertNot(is_start(FFile)),
    ?assertNot(lists:member({start, 0}, get_exports(FFile))),

    ?assertNot(is_beam(TextFile)),
    ?assertMatch("test/priv/test.txt", get_module_name(TextFile)),

    ok.

packbeam_prune_no_start_module_test() ->
    AVMFile = dest_dir("packbeam_prune_no_start_module_test.avm"),
    ?assertException(
        throw,
        _Term,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("d.beam"),
                test_beam_path("e.beam"),
                test_beam_path("f.beam"),
                "test/priv/test.txt"
            ],
            true,
            b
        )
    ),

    ok.

packbeam_dest_fail_test() ->
    ?assertMatch(
        {error, _},
        packbeam_api:create(
            "/tmp", [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                test_beam_path("e.beam"),
                "test/priv/test.txt"
            ]
        )
    ),

    ?assertMatch(
        {error, _},
        packbeam_api:create(
            "/usr/should_not_allowed.avm", [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                test_beam_path("e.beam"),
                "test/priv/test.txt"
            ]
        )
    ),

    ?assertMatch(
        {error, _},
        packbeam_api:create(
            "/likely_doesnt_exist/should_fail.avm", [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                test_beam_path("e.beam"),
                "test/priv/test.txt"
            ]
        )
    ),

    ok.

packbeam_src_fail_test() ->
    ?assertException(
        throw,
        _Term,
        packbeam_api:create(
            dest_dir("packbeam_src_fail_test.avm"), [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                test_beam_path("does_not_exist.beam"),
                "test/priv/test.txt"
            ]
        )
    ),

    ok.

packbeam_create_named_module_test() ->
    AVMFile = dest_dir("packbeam_list_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile, [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                {"test/priv/test.txt", "any/thing/you/want.txt"}
            ]
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),
    ?assertEqual(length(ParsedFiles), 5),

    [_AFile, _BFile, _CFile, _DFile, TextFile] = ParsedFiles,

    ?assertNot(is_beam(TextFile)),
    ?assertMatch("any/thing/you/want.txt", get_module_name(TextFile)),

    ok.

packbeam_list_test() ->
    AVMFile = dest_dir("packbeam_list_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                "test/priv/test.txt"
            ],
            true,
            b
        )
    ),

    packbeam_api:list(AVMFile),

    ?assertException(
        throw,
        _Term,
        packbeam_api:list(test_beam_path("d.beam"))
    ),

    ?assertException(
        throw,
        _Term,
        packbeam_api:list("/usr")
    ),

    ?assertException(
        throw,
        _Term,
        packbeam_api:list("/should_not_exist.txt")
    ),

    ok.

packbeam_create_dependent_avm_test() ->
    AVMFile = dest_dir("packbeam_create_dependent_avm_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile, [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                "test/priv/test.txt"
            ]
        )
    ),
    % io:format(user, "ParsedFiles1: ~p~n", [packbeam_api:list(AVMFile)]),

    AVMFile2 = dest_dir("packbeam_create_dependent_avm_test2.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile2,
            [
                test_beam_path("x.beam"),
                AVMFile
            ],
            true,
            x
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile2),

    ?assert(is_list(ParsedFiles)),
    ?assertEqual(length(ParsedFiles), 5),

    [FirstFile | _Rest] = ParsedFiles,
    ?assertEqual(get_module(FirstFile), x),
    ?assert(is_beam(FirstFile)),
    ?assert(is_start(FirstFile)),

    ?assert(parsed_file_contains_module(x, ParsedFiles)),
    ?assert(parsed_file_contains_module(a, ParsedFiles)),
    ?assert(parsed_file_contains_module(b, ParsedFiles)),
    ?assert(parsed_file_contains_module(c, ParsedFiles)),

    ok.

packbeam_extract_test() ->
    AVMFile = dest_dir("packbeam_extract_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile, [
                test_beam_path("a.beam"),
                test_beam_path("b.beam"),
                test_beam_path("c.beam"),
                test_beam_path("d.beam"),
                "test/priv/test.txt"
            ]
        )
    ),

    ScratchDir = create_scratch_dir("packbeam_extract_test"),
    ok = packbeam_api:extract(AVMFile, [], ScratchDir),

    ?assert(file_exists(ScratchDir ++ "/a.beam")),
    ?assert(file_exists(ScratchDir ++ "/b.beam")),
    ?assert(file_exists(ScratchDir ++ "/c.beam")),
    ?assert(file_exists(ScratchDir ++ "/d.beam")),
    ?assert(file_exists(ScratchDir ++ "/test/priv/test.txt")),

    ScratchDir2 = create_scratch_dir("packbeam_extract_test2"),
    ok = packbeam_api:extract(AVMFile, ["c.beam", "test/priv/test.txt"], ScratchDir2),

    ?assert(not file_exists(ScratchDir2 ++ "/a.beam")),
    ?assert(not file_exists(ScratchDir2 ++ "/b.beam")),
    ?assert(file_exists(ScratchDir2 ++ "/c.beam")),
    ?assert(not file_exists(ScratchDir2 ++ "/d.beam")),
    ?assert(file_exists(ScratchDir2 ++ "/test/priv/test.txt")),

    ScratchDir3 = create_scratch_dir("packbeam_extract_test3"),
    ok = packbeam_api:extract(AVMFile, ["c.beam", "does-not-exist"], ScratchDir3),

    ?assert(not file_exists(ScratchDir3 ++ "/a.beam")),
    ?assert(not file_exists(ScratchDir3 ++ "/b.beam")),
    ?assert(file_exists(ScratchDir3 ++ "/c.beam")),
    ?assert(not file_exists(ScratchDir3 ++ "/d.beam")),
    ?assert(not file_exists(ScratchDir3 ++ "/test/priv/test.txt")),

    ?assertException(
        throw,
        _Term,
        packbeam_api:extract(AVMFile ++ "-garbage", [], ScratchDir3)
    ),

    ?assertException(
        throw,
        _Term,
        packbeam_api:extract(AVMFile, [], ?BUILD_DIR ++ "does-not-exist")
    ),

    ?assertException(
        throw,
        _Term,
        packbeam_api:extract(AVMFile, [], ?BUILD_DIR ++ "packbeam_create_dependent_avm_test2.avm")
    ),

    ok.

packbeam_create_prune_supervisor_callback_test() ->
    %% Test that prune does not remove a module referenced only in a
    %% supervisor child spec literal. In this scenario:
    %%   start_mod (entrypoint) -> my_sup (via atom) -> my_worker (only in literal)
    %% The my_worker atom only appears in the literals table of my_sup,
    %% not in its atoms chunk or imports. Prune must still keep it.
    AVMFile = dest_dir("packbeam_prune_sup_callback_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("start_mod.beam"),
                test_beam_path("my_sup.beam"),
                test_beam_path("my_worker.beam"),
                test_beam_path("d.beam")
            ],
            #{prune => true}
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),

    %% start_mod calls my_sup, my_sup has my_worker only in literal child specs.
    %% d is not referenced by anyone.
    ?assert(parsed_file_contains_module(start_mod, ParsedFiles)),
    ?assert(parsed_file_contains_module(my_sup, ParsedFiles)),
    ?assert(parsed_file_contains_module(my_worker, ParsedFiles)),
    ?assertNot(parsed_file_contains_module(d, ParsedFiles)),

    %% Pruned file should be smaller than unpruned (d.beam was removed).
    UnprunedAVMFile = dest_dir("packbeam_prune_sup_callback_unpruned.avm"),
    ok = packbeam_api:create(
        UnprunedAVMFile,
        [
            test_beam_path("start_mod.beam"),
            test_beam_path("my_sup.beam"),
            test_beam_path("my_worker.beam"),
            test_beam_path("d.beam")
        ],
        #{}
    ),
    PrunedSize = filelib:file_size(AVMFile),
    UnprunedSize = filelib:file_size(UnprunedAVMFile),
    ?assert(PrunedSize < UnprunedSize),

    ok.

packbeam_create_prune_supervisor_callback_from_avm_test() ->
    %% Same as above, but with my_worker coming from a lib AVM file.
    %% This tests the AVM parsing path where uncompressed_literals
    %% may not be available.
    LibAVMFile = dest_dir("packbeam_prune_sup_callback_lib.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            LibAVMFile,
            [
                test_beam_path("my_sup.beam"),
                test_beam_path("my_worker.beam"),
                test_beam_path("d.beam")
            ],
            #{lib => true}
        )
    ),

    AVMFile = dest_dir("packbeam_prune_sup_callback_from_avm_test.avm"),
    ?assertMatch(
        ok,
        packbeam_api:create(
            AVMFile,
            [
                test_beam_path("start_mod.beam"),
                LibAVMFile
            ],
            #{prune => true}
        )
    ),

    ParsedFiles = packbeam_api:list(AVMFile),

    ?assert(is_list(ParsedFiles)),

    ?assert(parsed_file_contains_module(start_mod, ParsedFiles)),
    ?assert(parsed_file_contains_module(my_sup, ParsedFiles)),
    ?assert(parsed_file_contains_module(my_worker, ParsedFiles)),
    ?assertNot(parsed_file_contains_module(d, ParsedFiles)),

    ok.

packbeam_create_labt_test() ->
    Input = dest_dir("labt_input.avm"),
    Output = dest_dir("labt_output.avm"),
    Sources = [test_beam_path("a.beam"), test_beam_path("d.beam"), "test/priv/test.txt"],
    ok = packbeam_api:create(Input, Sources),
    Original = packbeam_api:list(Input),
    ok = packbeam_api:create(Output, [Input], #{avm_labels => #{}}),
    Packed = packbeam_api:list(Output),
    lists:foreach(
        fun({Before, After}) ->
            ?assertEqual(get_module_name(Before), get_module_name(After)),
            ?assertEqual(is_start(Before), is_start(After)),
            Data = packbeam_api:get_element_data(After),
            case is_beam(Before) of
                false ->
                    ?assertEqual(packbeam_api:get_element_data(Before), Data);
                true ->
                    {ok, _, OldChunks} = beam_lib:all_chunks(packbeam_api:get_element_data(Before)),
                    {ok, _, Chunks} = beam_lib:all_chunks(Data),
                    ?assertEqual(undefined, proplists:get_value("avmL", OldChunks)),
                    <<_:32/little, 1:16/little, _:16/little, _/binary>> = proplists:get_value(
                        "avmL", Chunks
                    ),
                    ?assertEqual(OldChunks, lists:keydelete("avmL", 1, Chunks))
            end
        end,
        lists:zip(Original, Packed)
    ),
    %% Direct BEAM input, pruning, and replacement of a preexisting narrow table.
    ok = packbeam_api:create(Input, Sources, #{avm_labels => #{label_width => auto}}),
    ok = packbeam_api:create(Output, [Input], #{prune => true, avm_labels => #{}}),
    Pruned = packbeam_api:list(Output),
    ?assertNot(parsed_file_contains_module(d, Pruned)),
    [A] = [F || F <- Pruned, is_beam(F)],
    {ok, _, AChunks} = beam_lib:all_chunks(packbeam_api:get_element_data(A)),
    <<_:32/little, 1:16/little, _:16/little, _/binary>> = proplists:get_value("avmL", AChunks),
    %% With generation off, retain supplied tables unchanged.
    ok = packbeam_api:create(Output, [Input]),
    ?assertEqual(packbeam_api:list(Input), packbeam_api:list(Output)),
    file:delete(Input),
    file:delete(Output).

packbeam_labt_native_only_test() ->
    NativePath = dest_dir("native.beam"),
    Input = dest_dir("native_input.avm"),
    Output = dest_dir("native_output.avm"),
    {ok, _, Chunks} = beam_lib:all_chunks(test_beam_path("a.beam")),
    NativeChunks = lists:keydelete("Code", 1, Chunks) ++ [{"avmN", <<1, 2, 3, 4>>}],
    {ok, Native} = beam_lib:build_module(NativeChunks),
    ok = file:write_file(NativePath, Native),
    Sources = [NativePath, test_beam_path("d.beam")],
    ok = packbeam_api:create(Input, Sources),
    [Before, _] = packbeam_api:list(Input),
    lists:foreach(
        fun({Files, Width}) ->
            ok = packbeam_api:create(Output, Files, #{avm_labels => #{label_width => Width}}),
            [After, Bytecode] = packbeam_api:list(Output),
            ?assertEqual(Before, After),
            {ok, _, PackedChunks} = beam_lib:all_chunks(packbeam_api:get_element_data(Bytecode)),
            ?assert(lists:keymember("avmL", 1, PackedChunks))
        end,
        [{Sources, 32}, {Sources, auto}, {[Input], 32}, {[Input], auto}]
    ),
    file:delete(NativePath),
    file:delete(Input),
    file:delete(Output).

packbeam_remove_lines_from_avm_test() ->
    Input = dest_dir("line_input.avm"),
    Output = dest_dir("line_output.avm"),
    Sources = [test_beam_path("a.beam"), test_beam_path("c.beam"), "test/priv/test.txt"],
    ok = packbeam_api:create(Input, Sources, #{avm_labels => #{}}),
    Original = packbeam_api:list(Input),
    %% Default repacking must preserve source locations as well as avmL.
    ok = packbeam_api:create(Output, [Input]),
    ?assertEqual(Original, packbeam_api:list(Output)),
    %% Listing, extraction, and deletion must not request stripping implicitly.
    ExtractDir = create_scratch_dir("line_extract"),
    ok = packbeam_api:extract(Input, ["a.beam"], ExtractDir),
    [A | _] = Original,
    ?assertEqual({ok, packbeam_api:get_element_data(A)}, file:read_file(ExtractDir ++ "/a.beam")),
    file:delete(ExtractDir ++ "/a.beam"),
    file:del_dir(ExtractDir),
    ok = packbeam_api:delete(Output, Input, ["c.beam"]),
    ?assertEqual([F || F <- Original, get_module_name(F) =/= "c.beam"], packbeam_api:list(Output)),
    ok = packbeam_api:create(Output, [Input], #{include_lines => false}),
    Stripped = packbeam_api:list(Output),
    ?assertEqual(length(Original), length(Stripped)),
    lists:foreach(
        fun({Before, After}) ->
            ?assertEqual(get_module_name(Before), get_module_name(After)),
            ?assertEqual(is_start(Before), is_start(After)),
            case is_beam(Before) of
                false ->
                    ?assertEqual(Before, After);
                true ->
                    {ok, _, OldChunks} = beam_lib:all_chunks(packbeam_api:get_element_data(Before)),
                    {ok, _, NewChunks} = beam_lib:all_chunks(packbeam_api:get_element_data(After)),
                    ?assert(lists:keymember("Line", 1, OldChunks)),
                    ?assert(lists:keymember("avmL", 1, OldChunks)),
                    ?assertEqual(lists:keydelete("Line", 1, OldChunks), NewChunks)
            end
        end,
        lists:zip(Original, Stripped)
    ),
    %% A subsequent import cannot restore stripped locations.
    ok = packbeam_api:create(Input, [Output]),
    ?assertEqual(Stripped, packbeam_api:list(Input)),
    file:delete(Input),
    file:delete(Output).

packbeam_labt_errors_preserve_output_test() ->
    Output = dest_dir("labt_errors.avm"),
    BadBeam = dest_dir("labt_bad.beam"),
    ok = file:write_file(Output, <<"keep this file">>),
    lists:foreach(
        fun(Options) ->
            ?assertThrow(
                {invalid_avm_labels_options, Options},
                packbeam_api:create(Output, [test_beam_path("a.beam")], #{avm_labels => Options})
            )
        end,
        [true, #{label_width => 16}, #{endian => big}]
    ),
    {ok, Bytes} = file:read_file(test_beam_path("a.beam")),
    {ok, _, Chunks} = beam_lib:all_chunks(Bytes),
    Code = <<16:32, 0:32, 192:32, 2:32, 1:32, 1, 16, 3>>,
    {ok, Bad} = beam_lib:build_module(lists:keystore("Code", 1, Chunks, {"Code", Code})),
    ok = file:write_file(BadBeam, Bad),
    ?assertThrow(
        {avm_labels, _, {unsupported_opcode, 192}},
        packbeam_api:create(Output, [BadBeam], #{avm_labels => #{}})
    ),
    ?assertEqual({ok, <<"keep this file">>}, file:read_file(Output)),
    file:delete(Output),
    file:delete(BadBeam).

file_exists(Path) ->
    filelib:is_file(Path).

%%
%% helper functions
%%

dest_dir(AVMFile) ->
    ?BUILD_DIR ++ AVMFile.

test_beam_path(BeamFile) ->
    ?TEST_BEAM_DIR ++ BeamFile.

get_module(ParsedFile) ->
    packbeam_api:get_element_module(ParsedFile).

get_module_name(ParsedFile) ->
    packbeam_api:get_element_name(ParsedFile).

get_exports(ParsedFile) ->
    proplists:get_value(exports, proplists:get_value(chunk_refs, ParsedFile)).

is_start(ParsedFile) ->
    packbeam_api:is_entrypoint(ParsedFile).

is_beam(ParsedFile) ->
    packbeam_api:is_beam(ParsedFile).

parsed_file_contains_module(Module, ParsedFiles) ->
    lists:any(
        fun(ParsedFile) ->
            get_module(ParsedFile) =:= Module
        end,
        ParsedFiles
    ).

create_scratch_dir(Name) ->
    ok = filelib:ensure_dir(?BUILD_DIR ++ "/" ++ Name ++ "/" ++ "dummy"),
    ?BUILD_DIR ++ "/" ++ Name.
