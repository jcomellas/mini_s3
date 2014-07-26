%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
%% Copyright 2014 UBNT Networks All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%

-module(ms3_signature).
-author("Drew Varner").

% -export([string_to_sign/7]).
-compile(export_all).

-type http_method() :: httpc:method().

-type header_name() :: string().
-type header_value() :: string() | undefined.

-type header() :: {header_name(), header_value()}.
-type headers() :: [header()].

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-spec get_auth_header(AccessKeyID     :: string(), 
                      SecretAccessKey :: string(), 
                      Location        :: mini_s3:location_constraint(),
                      Service         :: mini_s3:service(),
                      Method          :: http_method(),
                      URI             :: string(),
                      Headers         :: headers(),
                      RequestPayload  :: iodata(),
                      Datetime        :: calendar:datetime(),
                      Algorithm       :: crypto:hash_algorithms()) -> header().
    get_auth_header(KeyID,Key,Loc,Serv,Method,URI,Hdrs,Payload,Datetime,Alg) ->
        Res = canonical_request(Method, URI, Hdrs, Payload, Alg),
        {signed_headers, SignedHdrs, canonical_request, CReq} = Res,
        HashedCReq = hash_and_hex_encode(Alg, CReq),
        StringToSign = string_to_sign(Alg, Loc, Serv, Datetime, HashedCReq),
        Sig = get_signature(Key, Loc, Serv, StringToSign, Datetime, Alg),
        CredentialScope = credential_scope(Datetime, Loc, Serv),
        Val = [
               hash_algorithm_to_string(Alg),
               " Credential=", KeyID, $/, CredentialScope,
               ", SignedHeaders=", SignedHdrs,
               ", Signature=", Sig
              ],
        {"Authorization", lists:flatten(Val)}.
         
-spec get_signature(Key          :: string(), 
                    Location     :: mini_s3:location_constraint(),
                    Service      :: mini_s3:service(),
                    StringToSign :: iolist(),
                    Date         :: calendar:datetime(),
                    Algorithm    :: crypto:hash_algorithms()) ->
    HexString::string().
    get_signature(Key, Location, Service, StringToSign, Date, Algorithm) ->
    SigningKey = signing_key(Key, Location, Service, Date),
    hex_encode(crypto:hmac(Algorithm, SigningKey, StringToSign)).

-spec signing_key(SecretAccessKey  :: string(), 
                           Region  :: mini_s3:location_constraint(),
                           Service :: mini_s3:service(),
                           Date    :: calendar:datetime()) -> binary().
signing_key(SecretAccessKey, Region, Service, Date) ->
    {{Year, Month, Day}, _} = Date,
    DateString = io_lib:format("~4.10.0B~2.10.0B~2.10.0B", [Year, Month, Day]),
    DateKey = crypto:hmac(sha256, "AWS4" ++ SecretAccessKey, DateString),
    DateRegionKey = crypto:hmac(sha256, DateKey, atom_to_list(Region)),
    DateRegionServiceKey = crypto:hmac(sha256, DateRegionKey, atom_to_list(Service)),
    crypto:hmac(sha256, DateRegionServiceKey, "aws4_request").

%% @doc This method is Task 2 of the Anmazon Web Services Signature
%%      Version 4 signing process. Note that the Erlang implemntation
%%      doesn't actually return a string(), but an iolist().
%%      This saves us from having to join the lists together and it
%%      prevents us from breaking the string() typespec if we were
%%      to include integers greater than 255 (some unicode characters).
-spec string_to_sign(Alg        :: crypto:hash_algorithms(),
                     Location   :: mini_s3:location_constraint(),
                     Service    :: mini_s3:service(),
                     Datetime   :: calendar:datetime(),
                     HashedCReq :: iolist()) -> iolist().
string_to_sign(Alg, Location, Service, Datetime, HashedCReq) ->
    RequestDateTime = datetime_fmt(Datetime),
    [hash_algorithm_to_string(Alg), $\n,
     RequestDateTime, $\n,
     credential_scope(Datetime, Location, Service), $\n,
     HashedCReq
    ].

%% This method technically breaks the requirement in
%% Amazon Web Services Version 4 Signature Documentation that:
%% "The region and service name strings must be UTF-8 encoded."
%% However, most Erlang HTTP client libraries only accept headers
%% as `string()`. So, for now we are going to ignore this requirement.
-spec credential_scope(calendar:datetime(),       
                       mini_s3:location_constraint(),
                       mini_s3:service()) -> iolist().
credential_scope({Date, _Time} = _Datetime, LocationConstraint, Service) ->
    [date_fmt(Date), $/,
     atom_to_list(LocationConstraint), $/,
     atom_to_list(Service), $/,
     "aws4_request"].

-spec canonical_request(Method         :: http_method(),
                        URI            :: string(),
                        Headers        :: headers(),
                        RequestPayload :: iodata(),
                        HashAlgorithm  :: crypto:hash_algorithms()) -> string().
canonical_request(Method, URI, Headers, RequestPayload, HashAlgorithm) ->
    {ok, {_, _, _, _, Path, Query}} = http_uri:parse(URI),
    CURI = canonicalize_uri(Path, []),
    CQueryString = canonicalize_query_string(Query),
    {header_names,SignedHdrs,headers,CHdrs} = canonicalize_headers(Headers, []),
    canonical_request(Method,
                      CURI,
                      CQueryString,
                      CHdrs,
                      SignedHdrs,
                      RequestPayload,
                      HashAlgorithm).

-spec canonical_request(Method       :: http_method(),
                        CURI         :: string(),
                        CQueryString :: string(),
                        CHdrs        :: string(),
                        SignedHdrs   :: string(),
                        Payload      :: iodata(),
                        HashAlg      :: crypto:hash_algorithms()) -> string().
canonical_request(Method,CURI,CQueryString,CHdrs,SignedHdrs,Payload,HashAlg) ->
    HashedAndHexedPayload = hash_and_hex_encode(HashAlg, Payload),
    HTTPRequestMethod = string:to_upper(atom_to_list(Method)),
    CReq = string:join([HTTPRequestMethod,
                        CURI,
                        CQueryString,
                        CHdrs,
                        SignedHdrs,
                        HashedAndHexedPayload],
                        "\n"),
    {signed_headers, SignedHdrs, canonical_request, CReq}.

%% TODO: Stop adding things to tail of list

% A
canonicalize_uri(["../" | Rest], Acc) ->
    canonicalize_uri(Rest, Acc);
canonicalize_uri(["./" | Rest], Acc) ->
    canonicalize_uri(Rest, Acc);
% B
canonicalize_uri(["/./" | Rest], Acc) ->
    canonicalize_uri(["/" | Rest], Acc);
canonicalize_uri("/.", Acc) ->
    Acc;
% C
canonicalize_uri(["/../" | Rest], Acc) ->
    canonicalize_uri(["/"| Rest], remove_last_segment(Acc));
canonicalize_uri("/..", Acc) ->
    remove_last_segment(Acc);
canonicalize_uri(".", Acc) ->
    canonicalize_uri([], Acc);
canonicalize_uri("..", Acc) ->
    canonicalize_uri([], Acc);
canonicalize_uri([], Acc) ->
    Acc;
canonicalize_uri(URI, Acc) ->
    {First, Rest} = get_and_remove_first_segment(URI),
    canonicalize_uri(Rest, Acc ++ First).

get_and_remove_first_segment([$/ | Rest] = URI) ->
    lists:split(string:chr(Rest, $/), URI).

remove_last_segment(String) ->
    Start = string:rchr(String, $/),
    lists:sublist(String, Start - 1).

-spec canonicalize_headers(headers(), headers()) ->
    {header_names,string(),headers,string()} | {error,headers_cannot_be_empty}.
canonicalize_headers([], []) ->
    {error, headers_cannot_be_empty};
canonicalize_headers([], Acc) ->
    Headers = lists:sort(lists:reverse(Acc)),
    HeaderNames = proplists:get_keys(Headers),
    Headers1 = case length(HeaderNames) =:= length(Headers) of
        true ->
            Headers;
        false ->
            % Merge duplicate headers
            [{HN,
              string:join(lists:sort(proplists:get_all_values(HN, Headers)), ",")} || HN <- HeaderNames]
    end,
    Headers2 = lists:keysort(1, Headers1),
    HString = lists:flatten([[Name,$:,Value,$\n] || {Name, Value} <- Headers2]),
    HNamesString = string:join(lists:sort(HeaderNames), ";"),
    {header_names, HNamesString, headers, HString};
canonicalize_headers([{_, undefined} | Rest], Acc) ->
    canonicalize_headers(Rest, Acc);
canonicalize_headers([Header | Rest], Acc) ->
    canonicalize_headers(Rest, [canonicalize_header(Header) | Acc]).

canonicalize_header({Name, Value}) when is_atom(Name) ->
    canonicalize_header({atom_to_list(Name), Value});
canonicalize_header({Name, Value})  ->
    Name1 = string:to_lower(Name),
    Value1 = strip_non_quoted_spaces(Value),
    {Name1, Value1}.

%%  removes excess white space before and after values and from inside
%%  non-quoted strings, per RFC 2616 Section 4.2.
%%  http://tools.ietf.org/html/rfc2616#page-32
-spec strip_non_quoted_spaces(String::string()) -> Result::string().
strip_non_quoted_spaces(String) ->
    strip_non_quoted_spaces(none, string:strip(String), "").

%% The states mean:
%% * none  =  Nothing special is going on
%% * quote =  I'm inside a quoted string
%% * space =  I'm inside linear whitespace
%% 
%% If you're inside a quoted string, it doesn't matter
%% that you are in linear whitespace, and whitespace is
%% treated like any other character.
-spec strip_non_quoted_spaces(State  :: none | space | quote,
                              String :: string(),
                              Acc    :: string()) -> string().
strip_non_quoted_spaces(none, [$\s | Rest], Acc) ->
    strip_non_quoted_spaces(space,  Rest, [$\s | Acc]);
strip_non_quoted_spaces(none, [$\t | Rest], Acc) ->
    strip_non_quoted_spaces(space,  Rest, [$\s | Acc]);
strip_non_quoted_spaces(none, [$" | Rest], Acc) ->
    strip_non_quoted_spaces(quote,  Rest, [$" | Acc]);
strip_non_quoted_spaces(none, [Char | Rest], Acc) ->
    strip_non_quoted_spaces(none,  Rest, [Char | Acc]);
strip_non_quoted_spaces(space, [$\s | Rest], Acc) ->
    strip_non_quoted_spaces(space,  Rest, Acc);
strip_non_quoted_spaces(space, [$\t | Rest], Acc) ->
    strip_non_quoted_spaces(space,  Rest, Acc);
strip_non_quoted_spaces(space, [$" | Rest], Acc) ->
    strip_non_quoted_spaces(quote,  Rest, [$" | Acc]);
strip_non_quoted_spaces(space, [Char | Rest], Acc) ->
    strip_non_quoted_spaces(none,  Rest, [Char | Acc]);
strip_non_quoted_spaces(quote, [$" | Rest], Acc) ->
    strip_non_quoted_spaces(none,  Rest, [$" | Acc]);
strip_non_quoted_spaces(quote, [Char | Rest], Acc) ->
    strip_non_quoted_spaces(quote,  Rest, [Char | Acc]);
strip_non_quoted_spaces(_, "", Acc) ->
        lists:reverse(Acc).

-spec canonicalize_query_string(string()) -> string().
canonicalize_query_string("") ->
    "";
canonicalize_query_string("?") ->
    "";
canonicalize_query_string([$?| QueryString]) ->
    Tokens0 = string:tokens(QueryString, "&"),
    Tokens1 = [maybe_append_equal(T) || T <- Tokens0],
    SortedTokens = lists:sort(Tokens1),
    string:join(SortedTokens, "&").

-spec maybe_append_equal(String::string()) -> string().
maybe_append_equal(String) ->
    case string:chr(String, $=) =:= 0 of
        true  -> String ++ "=";
        false -> String
    end.

-spec hash_and_hex_encode(HashAlgorithm :: crypto:hash_algorithms(),
                          Data          :: iodata()) -> string().
hash_and_hex_encode(HashAlgorithm, Data) ->
    Hashed = crypto:hash(HashAlgorithm, Data),
    hex_encode(Hashed).

-spec hex_encode(Binary::binary()) -> string().
hex_encode(Binary) ->
    lists:flatten([io_lib:format("~2.16.0b",[X]) || <<X:8>> <= Binary]).

now_utc() ->
    erlang:localtime_to_universaltime(erlang:localtime()).

datetime_fmt({{Year,Month,Day}, {Hour,Min,Sec}}) ->
    io_lib:format("~4.10.0B~2.10.0B~2.10.0BT~2.10.0B~2.10.0B~2.10.0BZ",
                  [Year, Month, Day, Hour, Min, Sec]).

date_fmt({Year,Month,Day}) ->
    io_lib:format("~4.10.0B~2.10.0B~2.10.0B", [Year, Month, Day]).

-spec hash_algorithm_to_string(crypto:hash_algorithms()) -> string().
hash_algorithm_to_string(sha224) -> "AWS4-HMAC-SHA224";
hash_algorithm_to_string(sha256) -> "AWS4-HMAC-SHA256";
hash_algorithm_to_string(sha384) -> "AWS4-HMAC-SHA384";
hash_algorithm_to_string(sha512) -> "AWS4-HMAC-SHA512".

-spec atom_to_unicode_binary(Atom::atom()) -> binary().
atom_to_unicode_binary(Atom) ->
    unicode:characters_to_binary(atom_to_list(Atom), latin1).

-ifdef(TEST).

% TODO: eunit test Canonicalize URI

strip_non_quoted_spaces_test_() ->
    Tests = [
             {"abc"           , "abc"        },
             {"a  b  c"       , "a b c"      },
             {"  \"a  b  c\"" , "\"a  b  c\""},
             {"a\tb\tc"       , "a b c"      },
             {"\"a\tb\tc\""   , "\"a\tb\tc\""},
             {"  abc    "     , "abc"        },
             {"  a  \t bc    ", "a bc"       }
            ],
    [ ?_assertEqual(Expected, strip_non_quoted_spaces(String)) ||
                    {String, Expected} <- Tests].
-endif.
