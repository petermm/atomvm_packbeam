%% Copyright 2026 Peter M <petermm@gmail.com>
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

-module(packbeam_labt_tests).
-include_lib("eunit/include/eunit.hrl").

offsets_test() ->
    %% Label 2 precedes label 1. The move's long integer includes bytes that
    %% look like label and int_code_end opcodes; a byte search is not a scanner.
    Beam = beam(<<1, 32, 64, 25, 1, 3, 3, 1, 16, 19, 3>>, 3),
    {ok, Packed} = packbeam_labt:add(Beam, 32),
    ?assertEqual(
        <<10:32/little, 1:16/little, 3:16/little, 0:32/little, 9:32/little, 2:32/little>>,
        chunk(Packed, "avmL")
    ),
    ?assertEqual(chunk(Beam, "Code"), chunk(Packed, "Code")),
    ?assertEqual(undefined, chunk(Packed, "LabT")),
    {ok, Again} = packbeam_labt:add(Packed, 32),
    ?assertEqual(Packed, Again).

auto_width_test_() ->
    [
        ?_test(begin
            N = Size - 23,
            Returns = binary:copy(<<19>>, N),
            Beam = beam(<<1, 16, Returns/binary, 3>>, 2),
            {ok, Packed} = packbeam_labt:add(Beam, auto),
            End = Size - 21,
            ?assertEqual(
                <<End:32/little, Flag:16/little, 2:16/little, 0:Bits/little, 2:Bits/little>>,
                chunk(Packed, "avmL")
            ),
            {ok, Wide} = packbeam_labt:add(Packed, 32),
            ?assertEqual(
                <<End:32/little, 1:16/little, 2:16/little, 0:32/little, 2:32/little>>,
                chunk(Wide, "avmL")
            )
        end)
     || {Size, Flag, Bits} <- [{65535, 0, 16}, {65536, 1, 32}]
    ].

extended_operands_test_() ->
    %% Each encoded instruction has an independently counted byte length.
    [
        ?_test(begin
            Beam = beam(<<Instruction/binary, 1, 16, 3>>, 2),
            {ok, Packed} = packbeam_labt:add(Beam, 32),
            Offset = Length + 2,
            ?assertEqual(
                <<Offset:32/little, 1:16/little, 2:16/little, 0:32/little, Offset:32/little>>,
                chunk(Packed, "avmL")
            )
        end)
     || {Instruction, Length} <- [
            % inline float
            {<<64, 7, 1, 3, 0, 0, 0, 0, 0, 0, 3>>, 11},
            % tuple's source list
            {<<164, 3, 23, 32, 17, 33>>, 6},
            % float register
            {<<96, 39, 0, 3>>, 4},
            % two allocation pairs
            {<<16, 55, 32, 0, 16, 16, 32, 0>>, 8},
            % two-byte literal index
            {<<64, 71, 8, 17, 3>>, 5},
            % typed x register
            {<<64, 87, 19, 0, 3>>, 5},
            % typed y register, two-byte type
            {<<64, 87, 20, 8, 16, 3>>, 6},
            % long bignum
            {<<64, 249, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 3>>, 13}
        ]
    ].

malformed_code_test_() ->
    [
        ?_assertMatch({error, _}, packbeam_labt:add(beam(Code, Count), 32))
     || {Code, Count} <- [
            % missing terminator
            {<<1, 16>>, 2},
            % bytes after terminator
            {<<1, 16, 3, 19>>, 2},
            % duplicate definition
            {<<1, 16, 1, 16, 3>>, 2},
            % out of range
            {<<1, 32, 3>>, 2},
            % reserved label zero
            {<<1, 0, 3>>, 2},
            % missing definition
            {<<1, 16, 3>>, 3},
            % unsupported opcode
            {<<1, 16, 192, 3>>, 2},
            % unknown extended operand
            {<<1, 16, 64, 103, 3, 3>>, 2},
            % typed atom, not register
            {<<1, 16, 64, 87, 2, 0, 3, 3>>, 2},
            % truncated allocation list
            {<<1, 16, 16, 55, 32, 0, 16, 3>>, 2},
            % impossible list count
            {<<1, 16, 64, 23, 9, 255, 3, 3>>, 2},
            {<<1, 16, 3>>, 65536}
        ]
    ].

truncated_operands_test_() ->
    Code = <<1, 16, 64, 249, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 3, 3>>,
    [
        ?_assertMatch({error, _}, packbeam_labt:add(beam(binary:part(Code, 0, N), 2), 32))
     || N <- lists:seq(0, byte_size(Code) - 1)
    ].

unsupported_header_test_() ->
    [
        ?_test(begin
            {ok, Beam} = beam_lib:build_module([
                {"AtU8", <<1:32, 4, "labt">>}, {"Code", Header}
            ]),
            ?assertMatch({error, _}, packbeam_labt:add(Beam, 32))
        end)
     || Header <- [
            <<16:32, 1:32, 3:32, 2:32, 1:32, 1, 16, 3>>,
            <<16:32, 0:32, 192:32, 2:32, 1:32, 1, 16, 3>>,
            <<20:32, 0:32, 3:32, 2:32, 1:32, 0:32, 1, 16, 3>>
        ]
    ].

beam(Code, Labels) ->
    {ok, Beam} = beam_lib:build_module([
        {"AtU8", <<1:32, 4, "labt">>},
        {"Code", <<16:32, 0:32, 191:32, Labels:32, 1:32, Code/binary>>}
    ]),
    Beam.

chunk(Beam, Tag) ->
    {ok, _, Chunks} = beam_lib:all_chunks(Beam),
    proplists:get_value(Tag, Chunks).
