%%
%% Copyright 2026 Peter M <petermm@gmail.com>
%% Copyright Ericsson AB 1998-2026. All Rights Reserved.
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% @private
%% Generate AtomVM label tables without rewriting the original Code bytes.
-module(packbeam_labt).

-export([add/2]).

-spec add(binary(), 32 | auto) -> {ok, binary()} | {error, term()}.
add(Beam, Width) ->
    try
        case beam_lib:all_chunks(Beam) of
            {ok, _Module, Chunks} ->
                case proplists:get_value("Code", Chunks) of
                    undefined ->
                        %% Precompiled modules have native code but no bytecode labels.
                        check(lists:keymember("avmN", 1, Chunks), unsupported_code_header),
                        {ok, Beam};
                    Code ->
                        Payload = generate(Code, Width),
                        WithoutLabels = [Chunk || {Tag, _} = Chunk <- Chunks, Tag =/= "avmL"],
                        beam_lib:build_module(WithoutLabels ++ [{"avmL", Payload}])
                end;
            Error ->
                {error, {invalid_beam, Error}}
        end
    catch
        throw:{labt_error, Reason} -> {error, Reason}
    end.

generate(<<16:32, 0:32, MaxOpcode:32, NumLabels:32, _Functions:32, Code/binary>> = Chunk, Width) ->
    check(
        MaxOpcode >= 3 andalso MaxOpcode =< tuple_size(arities()), {unsupported_opcode, MaxOpcode}
    ),
    check(NumLabels > 0 andalso NumLabels =< 65535, {unsupported_label_count, NumLabels}),
    check(byte_size(Code) =< 16#FFFFFFFF, code_too_large),
    {End, Labels} = scan(Code, byte_size(Code), MaxOpcode, NumLabels, #{}),
    check(map_size(Labels) =:= NumLabels - 1, incomplete_labels),
    Offsets = [0 | [maps:get(I, Labels) || I <- lists:seq(1, NumLabels - 1)]],
    Bits =
        case Width of
            auto when byte_size(Chunk) =< 65535 -> 16;
            auto -> 32;
            32 -> 32
        end,
    Flags =
        case Bits of
            16 -> 0;
            32 -> 1
        end,
    Entries = <<<<Offset:Bits/little>> || Offset <- Offsets>>,
    <<End:32/little, Flags:16/little, NumLabels:16/little, Entries/binary>>;
generate(_, _) ->
    fail(unsupported_code_header).

%% AtomVM jumps to the byte AFTER a label definition, not to its opcode.
%% int_code_end, in contrast, identifies the opcode byte itself.
scan(<<1, Rest/binary>>, Size, MaxOpcode, NumLabels, Labels) ->
    {Label, Tail} = unsigned(Rest),
    check(Label > 0 andalso Label < NumLabels, {invalid_label, Label}),
    check(not maps:is_key(Label, Labels), {duplicate_label, Label}),
    scan(Tail, Size, MaxOpcode, NumLabels, Labels#{Label => Size - byte_size(Tail)});
scan(<<3>>, Size, _MaxOpcode, _NumLabels, Labels) ->
    {Size - 1, Labels};
scan(<<3, _/binary>>, _Size, _MaxOpcode, _NumLabels, _Labels) ->
    fail(trailing_code);
scan(<<Opcode, Rest/binary>>, Size, MaxOpcode, NumLabels, Labels) ->
    check(Opcode > 0 andalso Opcode =< MaxOpcode, {unsupported_opcode, Opcode}),
    Tail = skip_terms(element(Opcode, arities()), Rest),
    scan(Tail, Size, MaxOpcode, NumLabels, Labels);
scan(<<>>, _Size, _MaxOpcode, _NumLabels, _Labels) ->
    fail(missing_int_code_end).

skip_terms(0, Rest) ->
    Rest;
skip_terms(N, Rest) ->
    %% Every term takes at least one byte, including nested list elements.
    check(N =< byte_size(Rest), truncated_operand),
    skip_terms(N - 1, skip_term(Rest)).

skip_term(<<7, Rest/binary>>) ->
    %% Legacy inline float: eight raw bytes, not compact operands.
    drop(8, Rest);
skip_term(<<23, Rest/binary>>) ->
    {Count, Tail} = unsigned(Rest),
    skip_terms(Count, Tail);
skip_term(<<39, Rest/binary>>) ->
    {_Register, Tail} = unsigned(Rest),
    Tail;
skip_term(<<55, Rest/binary>>) ->
    {Count, Tail} = unsigned(Rest),
    skip_unsigneds(Count * 2, Tail);
skip_term(<<71, Rest/binary>>) ->
    {_Literal, Tail} = unsigned(Rest),
    Tail;
skip_term(<<87, Rest/binary>>) ->
    {Tag, _Register, Tail} = compact(Rest),
    check(Tag =:= 3 orelse Tag =:= 4, invalid_typed_register),
    {_Type, End} = unsigned(Tail),
    End;
skip_term(<<B, _/binary>> = Rest) when B band 7 =/= 7 ->
    {_Tag, _Value, Tail} = compact(Rest),
    Tail;
skip_term(<<B, _/binary>>) ->
    fail({unsupported_extended_tag, B});
skip_term(<<>>) ->
    fail(truncated_operand).

skip_unsigneds(0, Rest) ->
    Rest;
skip_unsigneds(N, Rest) ->
    check(N =< byte_size(Rest), truncated_operand),
    {_Value, Tail} = unsigned(Rest),
    skip_unsigneds(N - 1, Tail).

unsigned(Rest) ->
    case compact(Rest) of
        {0, Value, Tail} when is_integer(Value) -> {Value, Tail};
        {0, Value, Tail} when byte_size(Value) =< 4 -> {binary:decode_unsigned(Value), Tail};
        _ -> fail(invalid_unsigned_operand)
    end.

%% Keep large integer payloads as binaries: skipping a bignum must not construct
%% its value. Only unsigned control operands (lengths, labels, indices) need it.
compact(<<B, Rest/binary>>) when B band 7 =/= 7 ->
    Tag = B band 7,
    case B band 16#18 of
        N when N band 8 =:= 0 ->
            {Tag, B bsr 4, Rest};
        8 ->
            case Rest of
                <<Low, Tail/binary>> -> {Tag, ((B band 16#E0) bsl 3) bor Low, Tail};
                _ -> fail(truncated_operand)
            end;
        24 ->
            {Length, Tail} =
                case B bsr 5 of
                    7 ->
                        {Extra, End} = unsigned(Rest),
                        {Extra + 9, End};
                    L ->
                        {L + 2, Rest}
                end,
            check(Length =< byte_size(Tail), truncated_operand),
            <<Value:Length/binary, EndTail/binary>> = Tail,
            {Tag, Value, EndTail}
    end;
compact(_) ->
    fail(invalid_compact_operand).

drop(N, Rest) when byte_size(Rest) >= N ->
    <<_:N/binary, Tail/binary>> = Rest,
    Tail;
drop(_, _) ->
    fail(truncated_operand).

check(true, _) -> ok;
check(false, Reason) -> fail(Reason).

fail(Reason) -> throw({labt_error, Reason}).

%% Opcode arities from erlang/otp lib/compiler/src/genop.tab, format 0,
%% revision d199a49a01a2079afb6f2c5c9ae047cd4555e68d (through OTP 29 opcode 191).
%% Includes retired opcodes so older bytecode can be scanned too. This table
%% describes encoding only; it does not promise runtime support for an opcode.
%% Rows contain ten consecutive opcodes, starting at opcode 1.
% erlfmt:ignore Keep the opcode table in numbered groups of ten.
arities() ->
    {1,3,0,2,3,2,2,3,2,4,
     5,2,3,2,3,2,1,1,0,0,
     0,0,2,1,1,2,4,4,4,4,
     4,4,4,4,4,4,4,3,3,3,
     3,3,3,3,2,2,2,2,2,2,
     2,2,2,2,2,2,2,3,3,3,
     1,2,1,2,3,3,3,3,3,2,
     1,1,0,1,1,3,2,2,2,5,
     5,5,4,2,1,1,2,2,5,5,
     5,2,1,0,1,2,2,4,4,4,
     4,3,1,2,1,1,1,2,6,3,
     5,1,2,2,3,5,7,7,7,5,
     3,2,2,5,6,2,2,2,2,1,
     3,4,0,8,6,2,6,5,4,5,
     4,5,4,3,3,3,3,3,0,1,
     1,7,1,5,5,2,3,3,4,0,
     0,2,2,2,3,4,3,2,2,4,
     3,1,2,1,1,1,6,3,0,1,
     5,3,2,4,6,2,4,3,6,3,
     5}.
