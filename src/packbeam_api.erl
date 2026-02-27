%%
%% Copyright (c) dushin.net
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

%%-----------------------------------------------------------------------------
%% @doc A library used to generate an
%% <a href="http://github.com/bettio/AtomVM">AtomVM</a> AVM file from a set of
%% files (beam files, previously built AVM files, or even arbitrary data files).
%% @end
%%-----------------------------------------------------------------------------
-module(packbeam_api).

%% API exports
-export([
    create/2, create/3, create/4, create/5,
    create_from_binaries/1, create_from_binaries/2,
    list/1,
    extract/3,
    delete/3
]).

%% AVM Entry functions
-export([is_beam/1, is_entrypoint/1, get_element_name/1, get_element_data/1, get_element_module/1]).

% erlfmt:ignore We want to keep the block format
-define(AVM_HEADER,
    16#23, 16#21, 16#2f, 16#75,
    16#73, 16#72, 16#2f, 16#62,
    16#69, 16#6e, 16#2f, 16#65,
    16#6e, 16#76, 16#20, 16#41,
    16#74, 16#6f, 16#6d, 16#56,
    16#4d, 16#0a, 16#00, 16#00
).

-define(ALLOWED_CHUNKS, [
    "AtU8", "Code", "ExpT", "LocT", "ImpT", "LitU", "FunT", "StrT", "LitT", "avmN", "Type"
]).
-define(BEAM_START_FLAG, 1).
-define(BEAM_CODE_FLAG, 2).
-define(NORMAL_FILE_FLAG, 4).

-opaque avm_element() :: [atom() | {atom(), term()}].
-type path() :: string().
-type avm_element_name() :: string().
-type input_binary() :: {Name :: string(), Data :: binary()}.
-type options() :: #{
    prune => boolean(),
    lib => boolean(),
    start_module => module() | undefined,
    application_module => module() | undefined,
    include_lines => boolean()
}.

-export_type([
    path/0,
    avm_element/0,
    avm_element_name/0,
    input_binary/0,
    options/0
]).

-define(DEFAULT_OPTIONS, #{
    prune => false,
    lib => false,
    start_module => undefined,
    application_module => undefined,
    include_lines => true
}).

%%
%% Public API
%%

%%-----------------------------------------------------------------------------
%% @param   OutputPath the path to write the AVM file
%% @param   InputPaths a list of paths of beam files, AVM files, or normal data files
%% @returns ok if the file was created.
%% @throws  Reason::string()
%% @doc     Create an AVM file.
%%
%%          Equivalent to `create(OutputPath, InputPaths, DefaultOptions)'
%%
%%          where `DefaultOptions' is `#{
%%              prune => false,
%%              lib => false,
%%              start_module => undefined,
%%              application_module => undefined,
%%              include_lines => false
%%          }'
%%
%% @end
%%-----------------------------------------------------------------------------
-spec create(
    OutputPath :: path(),
    InputPaths :: [path()]
) -> ok | {error, Reason :: term()}.
create(OutputPath, InputPaths) ->
    create(OutputPath, InputPaths, ?DEFAULT_OPTIONS).

%%-----------------------------------------------------------------------------
%% @param   OutputPath the path to write the AVM file
%% @param   InputPaths a list of paths of beam files, AVM files, or normal data files
%% @param   Options creation options
%% @returns ok if the file was created.
%% @throws  Reason::string()
%% @doc     Create an AVM file.
%%
%%          This function will create an AVM file at the location specified in
%%          OutputPath, using the input files specified in InputPaths.
%% @end
%%-----------------------------------------------------------------------------
-spec create(
    OutputPath :: path(),
    InputPaths :: [path()],
    Options :: options()
) -> ok | {error, Reason :: term()}.
create(OutputPath, InputPaths, Options) ->
    #{
        prune := Prune,
        lib := Lib,
        start_module := StartModule,
        application_module := ApplicationModule,
        include_lines := IncludeLines
    } = maps:merge(?DEFAULT_OPTIONS, Options),
    ParsedFiles = parse_files(InputPaths, Lib, StartModule, IncludeLines),
    write_packbeam(
        OutputPath,
        case Prune of
            true -> prune(ParsedFiles, ApplicationModule);
            _ -> ParsedFiles
        end
    ).

%%-----------------------------------------------------------------------------
%% @param   InputBinaries a list of `{Name, Data}' pairs where `Name' determines
%%          the file type (.beam, .avm, or other) and `Data' is the file contents
%% @returns `{ok, AVMBinary}' where `AVMBinary' is the generated AVM file as a binary.
%% @doc     Create an AVM file in memory from binary inputs.
%%
%%          Equivalent to `create_from_binaries(InputBinaries, DefaultOptions)'
%% @end
%%-----------------------------------------------------------------------------
-spec create_from_binaries(
    InputBinaries :: [input_binary()]
) -> {ok, binary()} | {error, Reason :: term()}.
create_from_binaries(InputBinaries) ->
    create_from_binaries(InputBinaries, ?DEFAULT_OPTIONS).

%%-----------------------------------------------------------------------------
%% @param   InputBinaries a list of `{Name, Data}' pairs where `Name' determines
%%          the file type (.beam, .avm, or other) and `Data' is the file contents
%% @param   Options creation options
%% @returns `{ok, AVMBinary}' where `AVMBinary' is the generated AVM file as a binary.
%% @doc     Create an AVM file in memory from binary inputs.
%%
%%          This function behaves identically to `create/3' but accepts in-memory
%%          binaries instead of file paths and returns the AVM as a binary rather
%%          than writing it to disk.
%% @end
%%-----------------------------------------------------------------------------
-spec create_from_binaries(
    InputBinaries :: [input_binary()],
    Options :: options()
) -> {ok, binary()} | {error, Reason :: term()}.
create_from_binaries(InputBinaries, Options) ->
    try
        #{
            prune := Prune,
            lib := Lib,
            start_module := StartModule,
            application_module := ApplicationModule,
            include_lines := IncludeLines
        } = maps:merge(?DEFAULT_OPTIONS, Options),
        ParsedFiles = parse_files(InputBinaries, Lib, StartModule, IncludeLines),
        {ok,
            build_packbeam_binary(
                case Prune of
                    true -> prune(ParsedFiles, ApplicationModule);
                    _ -> ParsedFiles
                end
            )}
    catch
        _:Reason:Stacktrace ->
            io:format("packbeam_api error: ~p~n", [Reason]),
            io:format("packbeam_api stacktrace: ~p~n", [Stacktrace]),
            {error, Reason}
    end.

%%-----------------------------------------------------------------------------
%% @param   OutputPath the path to write the AVM file
%% @param   InputPaths a list of paths of beam files, AVM files, or normal data files
%% @param   Prune whether to prune the archive.  Without pruning, all found BEAM files are included
%%          in the output AVM file.  With pruning, then packbeam will attempt to
%%          determine which BEAM files are needed to run the application, depending
%%          on which modules are (transitively) referenced from the AVM entrypoint.
%% @param   StartModule if `undefined', then this parameter is a module that
%%          is intended to the the start module for the application.  This module
%%          will occur first in the generated AVM file.
%% @returns ok if the file was created.
%% @throws  Reason::string()
%% @deprecated This function is deprecated, and will be removed in the 0.9.0 release.  Use
%% `create/3' instead.
%% @doc     Create an AVM file.
%%
%%          Equivalent to create(OutputPath, InputPaths, undefined, Prune, StartModule).
%% @end
%% @hidden
%%-----------------------------------------------------------------------------
-spec create(
    OutputPath :: path(),
    InputPaths :: [path()],
    Prune :: boolean(),
    StartModule :: module() | undefined
) ->
    ok | {error, Reason :: term()}.
create(OutputPath, InputPaths, Prune, StartModule) ->
    io:format("WARNING: Deprecated function will be removed in the 0.9.0 release: ~p:create/4~n", [
        ?MODULE
    ]),
    Options = #{prune => Prune, start_module => StartModule},
    create(OutputPath, InputPaths, maps:merge(?DEFAULT_OPTIONS, Options)).

%%-----------------------------------------------------------------------------
%% @param   OutputPath the path to write the AVM file
%% @param   InputPaths a list of paths of beam files, AVM files, or normal data files
%% @param   ApplicationModule If not `undefined', then this parameter designates
%%          the name of an OTP application, from which additional dependencies
%%          will be computed.
%% @param   Prune whether to prune the archive.  Without pruning, all found BEAM files are included
%%          in the output AVM file.  With pruning, then packbeam will attempt to
%%          determine which BEAM files are needed to run the application, depending
%%          on which modules are (transitively) referenced from the AVM entrypoint.
%% @param   StartModule if `undefined', then this parameter is a module that
%%          is intended to the the start module for the application.  This module
%%          will occur first in the generated AVM file.
%% @returns ok if the file was created.
%% @throws  Reason::string()
%% @deprecated This function is deprecated, and will be removed in the 0.9.0 release.  Use
%% `create/3' instead.
%% @doc     Create an AVM file.
%%
%%          This function will create an AVM file at the location specified in
%%          OutputPath, using the input files specified in InputPaths.
%% @end
%% @hidden
%%-----------------------------------------------------------------------------
-spec create(
    OutputPath :: path(),
    InputPaths :: [path()],
    ApplicationModule :: module() | undefined,
    Prune :: boolean(),
    StartModule :: module() | undefined
) ->
    ok | {error, Reason :: term()}.
create(OutputPath, InputPaths, ApplicationModule, Prune, StartModule) ->
    io:format("WARNING: Deprecated function will be removed in the 0.9.0 release: ~p:create/5~n", [
        ?MODULE
    ]),
    Options = #{
        prune => Prune, start_module => StartModule, application_module => ApplicationModule
    },
    create(OutputPath, InputPaths, maps:merge(?DEFAULT_OPTIONS, Options)).

%%-----------------------------------------------------------------------------
%% @param   InputPath the AVM file from which to list elements
%% @returns list of element data
%% @throws  Reason::string()
%% @doc     List the contents of an AVM file.
%%
%%          This function will list the contents of an AVM file at the
%%          location specified in InputPath.
%% @end
%%-----------------------------------------------------------------------------
-spec list(InputPath :: path()) -> [avm_element()].
list(InputPath) ->
    case file_type(InputPath) of
        avm ->
            parse_file(InputPath, false, undefined, false);
        _ ->
            throw(io_lib:format("Expected AVM file: ~p", [InputPath]))
    end.

%%-----------------------------------------------------------------------------
%% @param   InputPath the AVM file from which to extract elements
%% @param   AVMElementNames a list of elements from the source AVM file to extract.  If
%%          empty, then extract all elements.
%% @param   OutputDir the directory to write the contents
%% @returns ok if the file was created.
%% @throws  Reason::string()
%% @doc     Extract all or selected elements from an AVM file.
%%
%%          This function will extract elements of an AVM file at the location specified in
%%          InputPath, specified by the supplied list of names.  The elements
%%          from the input AVM file will be written into the specified output directory,
%%          creating any subdirectories if the AVM file elements contain path information.
%% @end
%%-----------------------------------------------------------------------------
-spec extract(
    InputPath :: path(),
    AVMElementNames :: [avm_element_name()],
    OutputDir :: path()
) -> ok | {error, Reason :: term()}.
extract(InputPath, AVMElementNames, OutputDir) ->
    case file_type(InputPath) of
        avm ->
            ParsedFiles = parse_file(InputPath, false, undefined, false),
            write_files(filter_names(AVMElementNames, ParsedFiles), OutputDir);
        _ ->
            throw(io_lib:format("Expected AVM file: ~p", [InputPath]))
    end.

%%-----------------------------------------------------------------------------
%% @param   InputPath the AVM file from which to delete elements
%% @param   OutputPath the path to write the AVM file
%% @param   AVMElementNames a list of elements from the source AVM file to delete
%% @returns ok if the file was created.
%% @throws  Reason::string()
%% @doc     Delete selected elements of an AVM file.
%%
%%          This function will delete elements of an AVM file at the location specified in
%%          InputPath, specified by the supplied list of names.  The output AVM file
%%          is written to OutputPath, which may be the same as InputPath.
%% @end
%%-----------------------------------------------------------------------------
-spec delete(
    OutputPath :: path(),
    InputPath :: path(),
    AVMElementNames :: [avm_element_name()]
) -> ok | {error, Reason :: term()}.
delete(OutputPath, InputPath, AVMElementNames) ->
    case file_type(InputPath) of
        avm ->
            ParsedFiles = parse_file(InputPath, false, undefined, false),
            write_packbeam(OutputPath, remove_names(AVMElementNames, ParsedFiles));
        _ ->
            throw(io_lib:format("Expected AVM file: ~p", [InputPath]))
    end.

%%-----------------------------------------------------------------------------
%% @param   AVMElement An AVM file element
%% @returns the name of the element.
%% @doc     Return the name of the element.
%% @end
%%-----------------------------------------------------------------------------
-spec get_element_name(AVMElement :: avm_element()) -> avm_element_name().
get_element_name(AVMElement) ->
    proplists:get_value(element_name, AVMElement).

%%-----------------------------------------------------------------------------
%% @param   AVMElement An AVM file element
%% @returns the AVM element data.
%% @doc     Return AVM element data.
%% @end
%%-----------------------------------------------------------------------------
-spec get_element_data(AVMElement :: avm_element()) -> binary().
get_element_data(AVMElement) ->
    proplists:get_value(data, AVMElement).

%%-----------------------------------------------------------------------------
%% @param   AVMElement An AVM file element
%% @returns the AVM element module, if the element is a BEAM file; `undefined',
%% otherwise.
%% @doc     Return AVM element module, if the element is a BEAM file.
%% @end
%%-----------------------------------------------------------------------------
-spec get_element_module(AVMElement :: avm_element()) -> module() | undefined.
get_element_module(AVMElement) ->
    proplists:get_value(module, AVMElement).

%%-----------------------------------------------------------------------------
%% @param   AVMElement An AVM file element
%% @returns `true' if the AVM element is an entrypoint (i.e., exports a `start/0'
%% function); `false' otherwise.
%% @doc     Indicates whether the AVM file element is an entrypoint.
%% @end
%%-----------------------------------------------------------------------------
-spec is_entrypoint(AVMElement :: avm_element()) -> boolean().
is_entrypoint(AVMElement) ->
    (get_flags(AVMElement) band ?BEAM_START_FLAG) =:= ?BEAM_START_FLAG.

%%-----------------------------------------------------------------------------
%% @param   AVMElement An AVM file element
%% @returns `true' if the AVM element is a BEAM file; `false' otherwise.
%% @doc     Indicates whether the AVM file element is a BEAM file.
%% @end
%%-----------------------------------------------------------------------------
-spec is_beam(AVMElement :: avm_element()) -> boolean().
is_beam(AVMElement) ->
    (get_flags(AVMElement) band ?BEAM_CODE_FLAG) =:= ?BEAM_CODE_FLAG.

%%
%% Internal API functions
%%

%% @private
get_flags(AVMElement) ->
    proplists:get_value(flags, AVMElement).

%% @private
parse_files(InputPaths, Lib, StartModule, IncludeLines) ->
    Files = lists:foldl(
        fun(InputPath, Accum) ->
            Accum ++ parse_file(InputPath, Lib, StartModule, IncludeLines)
        end,
        [],
        InputPaths
    ),
    case StartModule of
        undefined ->
            Files;
        _ ->
            reorder_start_module(StartModule, Files)
    end.

%% @private
parse_file({Name, Data}, Lib, StartModule, IncludeLines) when is_binary(Data) ->
    parse_file(file_type(Name), Name, Lib, StartModule, Data, IncludeLines);
parse_file({InputPath, ModuleName}, Lib, StartModule, IncludeLines) ->
    parse_file(
        file_type(InputPath), ModuleName, Lib, StartModule, load_file(InputPath), IncludeLines
    );
parse_file(InputPath, Lib, StartModule, IncludeLines) ->
    parse_file(
        file_type(InputPath), InputPath, Lib, StartModule, load_file(InputPath), IncludeLines
    ).

%% @private
file_type(InputPath) ->
    case ends_with(InputPath, ".beam") of
        true ->
            beam;
        _ ->
            case ends_with(InputPath, ".avm") of
                true -> avm;
                _ -> normal
            end
    end.

%% @private
load_file(Path) ->
    case file:read_file(Path) of
        {ok, Data} ->
            Data;
        {error, Reason} ->
            throw(io_lib:format("Unable to load file ~s.  Reason: ~p", [Path, Reason]))
    end.

%% @private
prune(ParsedFiles, RootApplicationModule) ->
    case find_entrypoint(ParsedFiles) of
        false ->
            throw("No input beam files contain start/0 entrypoint");
        {value, Entrypoint} ->
            BeamFiles = lists:filter(fun is_beam/1, ParsedFiles),
            Modules = closure(Entrypoint, BeamFiles, [get_element_module(Entrypoint)]),
            ApplicationStartModules = find_application_modules(ParsedFiles, RootApplicationModule),
            ApplicationModules = find_dependencies(ApplicationStartModules, BeamFiles),
            filter_modules(Modules ++ ApplicationModules, ParsedFiles)
    end.

find_application_modules(_ParsedFiles, undefined) ->
    [];
find_application_modules(ParsedFiles, ApplicationModule) ->
    ApplicationSpecs = find_all_application_specs(ParsedFiles),
    find_application_start_modules(ParsedFiles, ApplicationSpecs, ApplicationModule).

find_all_application_specs(ParsedFiles) ->
    ApplicationFiles = lists:filter(
        fun is_application_file/1,
        ParsedFiles
    ),
    [get_application_spec(ApplicationFile) || ApplicationFile <- ApplicationFiles].

find_application_start_modules(ParsedFiles, ApplicationSpecs, ApplicationModule) ->
    case find_application_spec(ApplicationSpecs, ApplicationModule) of
        false ->
            [];
        {value, {application, _ApplicationModule, Properties}} ->
            ChildApplicationStartModules =
                case proplists:get_value(applications, Properties) of
                    Applications when is_list(Applications) ->
                        lists:foldl(
                            fun(Application, InnerAccum) ->
                                find_application_start_modules(
                                    ParsedFiles, ApplicationSpecs, Application
                                ) ++ InnerAccum
                            end,
                            [],
                            Applications
                        );
                    _ ->
                        []
                end,
            StartModules =
                case proplists:get_value(mod, Properties) of
                    {StartModule, _Args} when is_atom(StartModule) ->
                        [StartModule];
                    _ ->
                        []
                end,
            ChildApplicationStartModules ++ StartModules
    end.

find_dependencies(Entrypoints, BeamFiles) ->
    deduplicate(
        lists:flatten(
            [
                closure(
                    get_parsed_file(Entrypoint, BeamFiles),
                    BeamFiles,
                    [Entrypoint]
                )
             || Entrypoint <- Entrypoints
            ]
        )
    ).

find_application_spec(ApplicationSpecs, ApplicationModule) ->
    lists:search(
        fun({application, Module, _Properties}) ->
            Module =:= ApplicationModule
        end,
        ApplicationSpecs
    ).

get_application_spec(ApplicationFile) ->
    ApplicationData = get_element_data(ApplicationFile),
    <<_Size:4/binary, SerializedTerm/binary>> = ApplicationData,
    binary_to_term(SerializedTerm).

is_application_file(ParsedFile) ->
    case not is_beam(ParsedFile) of
        true ->
            ModuleName = get_element_name(ParsedFile),
            Components = string:split(ModuleName, "/", all),
            case Components of
                [_ModuleName, "priv", "application.bin"] ->
                    true;
                _ ->
                    false
            end;
        false ->
            false
    end.

%% @private
find_entrypoint(ParsedFiles) ->
    lists:search(fun is_entrypoint/1, ParsedFiles).

%% @private
closure(_Current, [], Accum) ->
    lists:reverse(Accum);
closure(Current, Candidates, Accum) ->
    CandidateModules = get_element_modules(Candidates),
    CurrentsImports = get_imports(Current),
    CurrentsAtoms = get_atoms(Current),
    DepModules = intersection(CurrentsImports ++ CurrentsAtoms, CandidateModules) -- Accum,
    lists:foldl(
        fun(DepModule, A) ->
            case lists:member(DepModule, A) of
                true ->
                    A;
                _ ->
                    NewCandidates = remove(DepModule, Candidates),
                    closure(get_parsed_file(DepModule, Candidates), NewCandidates, [DepModule | A])
            end
        end,
        Accum,
        DepModules
    ).

%% @private
remove(Module, ParsedFiles) ->
    [P || P <- ParsedFiles, Module =/= get_element_module(P)].

%% @private
get_imports(ParsedFile) ->
    Imports = proplists:get_value(imports, proplists:get_value(chunk_refs, ParsedFile)),
    lists:usort([M || {M, _F, _A} <- Imports]).

%% @private
get_atoms(ParsedFile) ->
    AtomsT = [
        Atom
     || {_Index, Atom} <- proplists:get_value(atoms, proplists:get_value(chunk_refs, ParsedFile))
    ],
    AtomsFromLiterals = get_atom_literals(proplists:get_value(uncompressed_literals, ParsedFile)),
    lists:usort(AtomsT ++ AtomsFromLiterals).

%% @private
get_atom_literals(undefined) ->
    [];
get_atom_literals(UncompressedLiterals) ->
    <<NumLiterals:32, Rest/binary>> = UncompressedLiterals,
    get_atom_literals(NumLiterals, Rest, []).

%% @private
get_atom_literals(0, <<"">>, Accum) ->
    Accum;
get_atom_literals(I, Data, Accum) ->
    <<Length:32, StartData/binary>> = Data,
    <<EncodedLiteral:Length/binary, Rest/binary>> = StartData,
    Literal = binary_to_term(EncodedLiteral),
    ExtractedAtoms = extract_atoms(Literal, []),
    get_atom_literals(I - 1, Rest, ExtractedAtoms ++ Accum).

%% @private
extract_atoms(Term, Accum) when is_atom(Term) ->
    [Term | Accum];
extract_atoms(Term, Accum) when is_tuple(Term) ->
    extract_atoms(tuple_to_list(Term), Accum);
extract_atoms(Term, Accum) when is_map(Term) ->
    extract_atoms(maps:to_list(Term), Accum);
extract_atoms([H | T], Accum) ->
    HeadAtoms = extract_atoms(H, []),
    extract_atoms(T, HeadAtoms ++ Accum);
extract_atoms(_Term, Accum) ->
    Accum.

%% @private
get_element_modules(ParsedFiles) ->
    [get_element_module(ParsedFile) || ParsedFile <- ParsedFiles].

%% @private
get_parsed_file(Module, ParsedFiles) ->
    SearchResult = lists:search(
        fun(ParsedFile) ->
            get_element_module(ParsedFile) =:= Module
        end,
        ParsedFiles
    ),
    case SearchResult of
        {value, V} ->
            V;
        false ->
            exit({module_not_found, Module, ParsedFiles})
    end.

%% @private
intersection(A, B) ->
    lists:filter(
        fun(E) ->
            lists:member(E, B)
        end,
        A
    ).

%% @private
filter_modules(Modules, ParsedFiles) ->
    lists:filter(
        fun(ParsedFile) ->
            case is_beam(ParsedFile) of
                true ->
                    lists:member(get_element_module(ParsedFile), Modules);
                _ ->
                    true
            end
        end,
        ParsedFiles
    ).

%% @private
parse_file(beam, _ModuleName, Lib, StartModule, Data, IncludeLines) ->
    {ok, Module, Chunks} = beam_all_chunks(Data),
    {UncompressedChunks, UncompressedLiterals} = maybe_uncompress_literals(Chunks),
    FilteredChunks = filter_chunks(UncompressedChunks, IncludeLines),
    {ok, Binary} = beam_build_module(FilteredChunks),
    ChunkRefs = beam_named_chunks(Chunks, [imports, exports, atoms]),
    Exports = proplists:get_value(exports, ChunkRefs),
    Flags =
        if
            StartModule =:= Module ->
                ?BEAM_CODE_FLAG bor ?BEAM_START_FLAG;
            StartModule =:= undefined andalso Lib =:= false ->
                case lists:member({start, 0}, Exports) of
                    true ->
                        ?BEAM_CODE_FLAG bor ?BEAM_START_FLAG;
                    _ ->
                        ?BEAM_CODE_FLAG
                end;
            true ->
                ?BEAM_CODE_FLAG
        end,
    [
        [
            {module, Module},
            {element_name, io_lib:format("~s.beam", [atom_to_list(Module)])},
            {flags, Flags},
            {data, Binary},
            {chunk_refs, ChunkRefs},
            {uncompressed_literals, UncompressedLiterals}
        ]
    ];
parse_file(avm, ModuleName, Lib, StartModule, Data, _IncludeLines) ->
    case Data of
        <<?AVM_HEADER, AVMData/binary>> ->
            parse_avm_data(Lib, StartModule, AVMData);
        _ ->
            throw(io_lib:format("Invalid AVM header: ~p", [ModuleName]))
    end;
parse_file(normal, ModuleName, _Lib, _StartModule, Data, _IncludeLines) ->
    DataSize = byte_size(Data),
    Blob = <<DataSize:32, Data/binary>>,
    [[{element_name, ModuleName}, {flags, ?NORMAL_FILE_FLAG}, {data, Blob}]].

%% @private
reorder_start_module(StartModule, Files) ->
    {StartProps, Other} =
        lists:partition(
            fun(Props) ->
                % io:format("Props: ~w~n", [Props]),
                case get_element_module(Props) of
                    StartModule ->
                        case is_entrypoint(Props) of
                            true -> true;
                            _ -> throw({start_module_not_start_beam, StartModule})
                        end;
                    _ ->
                        false
                end
            end,
            Files
        ),
    case StartProps of
        [] ->
            throw({start_module_not_found, StartModule});
        _ ->
            StartProps ++ Other
    end.

%% @private
parse_avm_data(Lib, StartModule, AVMData) ->
    parse_avm_data(Lib, StartModule, AVMData, []).

%% @private
parse_avm_data(_Lib, _StartModule, <<"">>, Accum) ->
    lists:reverse(Accum);
parse_avm_data(_Lib, _StartModule, <<0:32/integer, _AVMRest/binary>>, Accum) ->
    lists:reverse(Accum);
parse_avm_data(Lib, StartModule, <<Size:32/integer, AVMRest/binary>>, Accum) ->
    SizeWithoutSizeField = Size - 4,
    case SizeWithoutSizeField =< erlang:byte_size(AVMRest) of
        true ->
            <<AVMBeamData:SizeWithoutSizeField/binary, AVMNext/binary>> = AVMRest,
            Beam0 = parse_beam(AVMBeamData, [], in_header, 0, []),
            {flags, BeamFlags0} = lists:keyfind(flags, 1, Beam0),
            BeamModule =
                case lists:keyfind(module, 1, Beam0) of
                    false -> undefined;
                    {module, BeamModule0} -> BeamModule0
                end,
            BeamFlags1 =
                if
                    Lib ->
                        BeamFlags0 band (bnot ?BEAM_START_FLAG);
                    BeamModule =:= undefined ->
                        BeamFlags0;
                    StartModule =:= BeamModule ->
                        BeamFlags0 bor ?BEAM_START_FLAG;
                    StartModule =/= undefined ->
                        BeamFlags0 band (bnot ?BEAM_START_FLAG);
                    true ->
                        BeamFlags0
                end,
            Beam1 = lists:keystore(flags, 1, Beam0, {flags, BeamFlags1}),
            parse_avm_data(Lib, StartModule, AVMNext, [Beam1 | Accum]);
        _ ->
            throw(
                io_lib:format("Invalid AVM data size: ~p (AVMRest=~p)", [
                    Size, erlang:byte_size(AVMRest)
                ])
            )
    end.

%% @private
parse_beam(<<Flags:32, _Reserved:32, Rest/binary>>, [], in_header, Pos, Accum) ->
    parse_beam(Rest, [], in_element_name, Pos + 8, [{flags, Flags} | Accum]);
parse_beam(<<0:8, Rest/binary>>, Tmp, in_element_name, Pos, Accum) ->
    ModuleName = lists:reverse(Tmp),
    case (Pos + 1) rem 4 of
        0 ->
            parse_beam(Rest, Tmp, in_data, Pos, [{element_name, ModuleName} | Accum]);
        _ ->
            parse_beam(Rest, [], eat_padding, Pos + 1, [{element_name, ModuleName} | Accum])
    end;
parse_beam(<<C:8, Rest/binary>>, Tmp, in_element_name, Pos, Accum) ->
    parse_beam(Rest, [C | Tmp], in_element_name, Pos + 1, Accum);
parse_beam(<<0:8, Rest/binary>>, Tmp, eat_padding, Pos, Accum) ->
    case (Pos + 1) rem 4 of
        0 ->
            parse_beam(Rest, Tmp, in_data, Pos, Accum);
        _ ->
            parse_beam(Rest, Tmp, eat_padding, Pos + 1, Accum)
    end;
parse_beam(Bin, Tmp, eat_padding, Pos, Accum) ->
    parse_beam(Bin, Tmp, in_data, Pos, Accum);
parse_beam(Data, _Tmp, in_data, _Pos, Accum) ->
    case is_beam(Accum) orelse is_entrypoint(Accum) of
        true ->
            StrippedData = strip_padding(Data),
            {ok, {Module, ChunkRefs}} = beam_lib:chunks(
                StrippedData, [imports, exports, atoms, "LitT", "LitU"], [allow_missing_chunks]
            ),
            [
                {module, Module},
                {chunk_refs, ChunkRefs},
                {uncompressed_literals, get_uncompressed_literals(ChunkRefs)},
                {data, StrippedData}
                | Accum
            ];
        _ ->
            [{data, Data} | Accum]
    end.

strip_padding(<<0:8, Rest/binary>>) ->
    strip_padding(Rest);
strip_padding(Data) ->
    Data.

%% @private
get_uncompressed_literals(ChunkRefs) ->
    case proplists:get_value("LitT", ChunkRefs) of
        missing_chunk ->
            case proplists:get_value("LitU", ChunkRefs) of
                missing_chunk -> undefined;
                LitU -> LitU
            end;
        <<0:32, Data/binary>> ->
            Data;
        <<_Size:4/binary, Data/binary>> ->
            zlib:uncompress(Data)
    end.

%% @private
maybe_uncompress_literals(Chunks) ->
    case proplists:get_value("LitT", Chunks) of
        undefined ->
            {Chunks, undefined};
        <<0:32, Data/binary>> ->
            {Chunks, Data};
        <<_Size:4/binary, Data/binary>> ->
            do_uncompress_literals(Chunks, Data)
    end.

%% @private
do_uncompress_literals(Chunks, Data) ->
    UncompressedData = zlib:uncompress(Data),
    {
        lists:keyreplace(
            "LitT",
            1,
            Chunks,
            {"LitU", UncompressedData}
        ),
        UncompressedData
    }.

%% @private
build_packbeam_binary(ParsedFiles) ->
    iolist_to_binary(
        [<<?AVM_HEADER>> | [pack_data(ParsedFile) || ParsedFile <- ParsedFiles]] ++
            [create_header(0, 0, <<"end">>)]
    ).

%% @private
write_packbeam(OutputFilePath, ParsedFiles) ->
    file:write_file(OutputFilePath, build_packbeam_binary(ParsedFiles)).

%% @private
pack_data(ParsedFile) ->
    ModuleName = list_to_binary(get_element_name(ParsedFile)),
    Flags = get_flags(ParsedFile),
    Data = get_element_data(ParsedFile),
    HeaderSize = header_size(ModuleName),
    HeaderPadding = create_padding(HeaderSize),
    DataSize = byte_size(Data),
    DataPadding = create_padding(DataSize),
    Size = HeaderSize + byte_size(HeaderPadding) + DataSize + byte_size(DataPadding),
    Header = create_header(Size, Flags, ModuleName),
    <<Header/binary, HeaderPadding/binary, Data/binary, DataPadding/binary>>.

%% @private
header_size(ModuleName) ->
    4 + 4 + 4 + byte_size(ModuleName) + 1.

%% @private
create_header(Size, Flags, ModuleName) ->
    <<Size:32, Flags:32, 0:32, ModuleName/binary, 0:8>>.

%% @private
create_padding(Size) ->
    case Size rem 4 of
        0 -> <<"">>;
        K -> list_to_binary(lists:duplicate(4 - K, 0))
    end.

%% @private
ends_with(String, Suffix) when is_list(String) ->
    ends_with(list_to_binary(String), Suffix);
ends_with(String, Suffix) when is_list(Suffix) ->
    ends_with(String, list_to_binary(Suffix));
ends_with(String, Suffix) when is_binary(String), is_binary(Suffix) ->
    SuffixSize = byte_size(Suffix),
    case String of
        <<_:(byte_size(String) - SuffixSize)/binary, Suffix/binary>> -> true;
        _ -> false
    end.

%% @private
%% Parse all chunks from a BEAM binary without beam_lib (avoids ets dependency).
%% Returns {ok, Module, [{Tag, Data}]} where Tag is a string like "AtU8".
beam_all_chunks(<<$F, $O, $R, $1, _Size:32, $B, $E, $A, $M, Rest/binary>>) ->
    Chunks = beam_parse_chunks(Rest, []),
    Module = beam_module_from_chunks(Chunks),
    {ok, Module, Chunks}.

beam_parse_chunks(<<>>, Acc) ->
    lists:reverse(Acc);
beam_parse_chunks(<<Tag:4/binary, Size:32, Rest/binary>>, Acc) ->
    PaddedSize = Size + ((4 - (Size rem 4)) rem 4),
    <<Data:Size/binary, _Pad:(PaddedSize - Size)/binary, Next/binary>> = Rest,
    beam_parse_chunks(Next, [{binary_to_list(Tag), Data} | Acc]);
beam_parse_chunks(_, Acc) ->
    lists:reverse(Acc).

beam_module_from_chunks(Chunks) ->
    {_, AtU8} = lists:keyfind("AtU8", 1, Chunks),
    <<_Count:32, _Rest/binary>> = AtU8,
    %% First atom (index 0) after count is the module name
    <<_:32, Len:8, Name:Len/binary, _/binary>> = AtU8,
    binary_to_atom(Name, utf8).

%% @private
%% Rebuild a BEAM binary from a chunk list without beam_lib.
beam_build_module(Chunks) ->
    ChunkBins = [begin
        Tag = list_to_binary(T),
        Size = byte_size(D),
        Pad = binary:copy(<<0>>, (4 - (Size rem 4)) rem 4),
        <<Tag/binary, Size:32, D/binary, Pad/binary>>
    end || {T, D} <- Chunks],
    Body = iolist_to_binary(ChunkBins),
    TotalSize = byte_size(Body) + 4,  %% +4 for "BEAM"
    {ok, <<"FOR1", TotalSize:32, "BEAM", Body/binary>>}.

%% @private
%% Extract decoded imports/exports/atoms from raw chunks (mirrors beam_lib:chunks/2).
beam_named_chunks(Chunks, Names) ->
    %% Decode atom table first so exports/imports can resolve names.
    Atoms = case lists:keyfind("AtU8", 1, Chunks) of
        false -> [];
        {_, AtomData} ->
            <<_Count:32, Rest/binary>> = AtomData,
            beam_decode_atoms(Rest, [])
    end,
    AtomTable = list_to_tuple(Atoms),
    lists:filtermap(fun(Name) ->
        RawTag = case Name of
            atoms   -> "AtU8";
            exports -> "ExpT";
            imports -> "ImpT"
        end,
        case lists:keyfind(RawTag, 1, Chunks) of
            false -> false;
            {_, Data} -> {true, {Name, beam_decode_chunk(Name, Data, AtomTable)}}
        end
    end, Names).

beam_decode_atoms(<<>>, Acc) -> lists:reverse(Acc);
beam_decode_atoms(<<Len:8, Name:Len/binary, Rest/binary>>, Acc) ->
    beam_decode_atoms(Rest, [binary_to_atom(Name, utf8) | Acc]).

beam_decode_chunk(atoms, <<_Count:32, Rest/binary>>, _AtomTable) ->
    Atoms = beam_decode_atoms(Rest, []),
    lists:zip(lists:seq(0, length(Atoms) - 1), Atoms);
beam_decode_chunk(exports, <<Count:32, Rest/binary>>, AtomTable) ->
    beam_decode_fa_table(Count, Rest, AtomTable, []);
beam_decode_chunk(imports, <<Count:32, Rest/binary>>, AtomTable) ->
    beam_decode_mfa_table(Count, Rest, AtomTable, []);
beam_decode_chunk(_, _, _) ->
    [].

%% ExpT: {_ModIdx:32, FunIdx:32, Arity:32} — resolve FunIdx against atom table
beam_decode_fa_table(0, _, _, Acc) -> lists:reverse(Acc);
beam_decode_fa_table(N, <<_Mod:32, Fun:32, Arity:32, Rest/binary>>, AtomTable, Acc) ->
    FunAtom = element(Fun + 1, AtomTable),
    beam_decode_fa_table(N - 1, Rest, AtomTable, [{FunAtom, Arity} | Acc]).

%% ImpT: {ModIdx:32, FunIdx:32, Arity:32}
%% Atom indices may reference atoms not present in AtU8 (e.g. from other modules),
%% so guard against out-of-range with a safe lookup.
beam_decode_mfa_table(0, _, _, Acc) -> lists:reverse(Acc);
beam_decode_mfa_table(N, <<Mod:32, Fun:32, Arity:32, Rest/binary>>, AtomTable, Acc) ->
    Size = tuple_size(AtomTable),
    ModAtom = if Mod + 1 =< Size -> element(Mod + 1, AtomTable); true -> Mod end,
    FunAtom = if Fun + 1 =< Size -> element(Fun + 1, AtomTable); true -> Fun end,
    beam_decode_mfa_table(N - 1, Rest, AtomTable, [{ModAtom, FunAtom, Arity} | Acc]).

%% @private
filter_chunks(Chunks, IncludeLines) ->
    AllowedChunks = allowed_chunks(IncludeLines),
    lists:filter(
        fun({Tag, _Data}) -> lists:member(Tag, AllowedChunks) end,
        Chunks
    ).

allowed_chunks(false) ->
    ?ALLOWED_CHUNKS;
allowed_chunks(true) ->
    ["Line" | ?ALLOWED_CHUNKS].

%% @private
remove_names(Names, ParsedFiles) ->
    lists:filter(
        fun(ParsedFile) ->
            ModuleName = get_element_name(ParsedFile),
            not lists:member(ModuleName, Names)
        end,
        ParsedFiles
    ).

%% @private
write_files(ParsedFiles, OutputDir) ->
    case filelib:is_dir(OutputDir) of
        true ->
            io:format("Writing to ~s ...~n", [OutputDir]),
            lists:foreach(
                fun(ParsedFile) ->
                    ModuleName = get_element_name(ParsedFile),
                    Path = OutputDir ++ "/" ++ ModuleName,
                    case filelib:ensure_dir(Path) of
                        ok ->
                            io:format("x ~s~n", [ModuleName]),
                            RawData = get_element_data(ParsedFile),
                            Data =
                                case file_type(ModuleName) of
                                    normal ->
                                        <<Size:32, Rest/binary>> = RawData,
                                        <<Contents:Size/binary, _/binary>> = Rest,
                                        Contents;
                                    _ ->
                                        RawData
                                end,
                            file:write_file(Path, Data);
                        Error ->
                            throw(Error)
                    end
                end,
                ParsedFiles
            );
        _ ->
            throw(enoent)
    end.

%% @private
filter_names([], ParsedFiles) ->
    ParsedFiles;
filter_names(Names, ParsedFiles) ->
    lists:filter(
        fun(ParsedFile) ->
            ModuleName = get_element_name(ParsedFile),
            lists:member(ModuleName, Names)
        end,
        ParsedFiles
    ).

%% @private
deduplicate([]) ->
    [];
deduplicate([H | T]) ->
    [H | [X || X <- deduplicate(T), X /= H]].
