%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
%% Amazon Simple Storage Service (S3)
%% Copyright 2010 Brian Buchanan. All Rights Reserved.
%% Copyright 2012 Opscode, Inc. All Rights Reserved.
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

-module(mini_s3).

-export([new/1,
         new/2,
         new/3,
         create_bucket/3,
         create_bucket/4,
         delete_bucket/1,
         delete_bucket/2,
         get_bucket_attribute/2,
         get_bucket_attribute/3,
         list_buckets/0,
         list_buckets/1,
         set_bucket_attribute/3,
         set_bucket_attribute/4,
         list_objects/2,
         list_objects/3,
         list_object_versions/2,
         list_object_versions/3,
         copy_object/5,
         copy_object/6,
         delete_object/2,
         delete_object/3,
         delete_object_version/3,
         delete_object_version/4,
         get_object/3,
         get_object/4,
         get_object_acl/2,
         get_object_acl/3,
         get_object_acl/4,
         get_object_torrent/2,
         get_object_torrent/3,
         get_object_metadata/3,
         get_object_metadata/4,
         s3_url/6,
         put_object/5,
         put_object/6,
         set_object_acl/3,
         set_object_acl/4]).

-export([manual_start/0,
         make_authorization/10,
         make_signed_url_authorization/5]).

-ifdef(TEST).
-compile([export_all]).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("internal.hrl").
-include_lib("xmerl/include/xmerl.hrl").
-include_lib("eunit/include/eunit.hrl").

-export_type([config/0,
              settable_bucket_attribute_name/0,
              bucket_acl/0,
              location_constraint/0]).

-opaque config() :: record(config).

-type bucket_access_type() :: virtual_hosted | path.

-type settable_bucket_attribute_name() :: acl
                                        | logging
                                        | request_payment
                                        | versioning.

-type bucket_acl() :: private
                    | public_read
                    | public_read_write
                    | authenticated_read
                    | bucket_owner_read
                    | bucket_owner_full_control.

-type credentials() :: {credentials, baked_in, string(), string()} |
                       {credentials, iam}.

-type location_constraint() :: none
                             | us_west_1
                             | eu.

-type permission() :: full_control
                    | write
                    | write_acp
                    | read
                    | read_acp.

-type header()  :: {string(), string() | undefined}.

-type headers() :: [header()].

-type response() :: {ok, {{pos_integer(), string()}, headers(), binary()}}
                  | {error, atom()}.

-type post_data() :: {iodata(), string()} | iodata().

-type method() :: get | head | post | put | delete | trace | 
                  options | connect | patch.

%% This is a helper function that exists to make development just a
%% wee bit easier
-spec manual_start() -> ok.
manual_start() ->
    ok = application:start(asn1),
    ok = application:start(crypto),
    ok = application:start(public_key),
    ok = application:start(ssl),
    ok = application:start(inets),
    ok = application:start(lhttpc).
    

-spec new(credentials()) -> config().
new({credentials, baked_in, AccessKeyID, SecretAccessKey}) ->
    #config{
       credentials_store=baked_in,
       access_key_id=AccessKeyID,
       secret_access_key=SecretAccessKey};
new({credentials, iam}) ->
    #config{credentials_store=iam}.

-spec new(credentials(), string()) -> config().
new(Credentials, Host) ->
    Config = new(Credentials),
    Config#config{s3_url=Host}.

-spec new(credentials(), string(), bucket_access_type()) -> config().
new(Credentials, Host, BucketAccessType) ->
    Config = new(Credentials),
    Config#config{s3_url=Host,
                  bucket_access_type=BucketAccessType}.

-spec copy_object(string(), string(), string(),
                  string(), proplists:proplist()) -> proplists:proplist().
copy_object(DestBucketName, DestKeyName, SrcBucketName, SrcKeyName, Options) ->
    copy_object(DestBucketName, DestKeyName, SrcBucketName,
                SrcKeyName, Options, default_config()).

-spec copy_object(string(), string(), string(), string(),
                  proplists:proplist(), config()) -> proplists:proplist().
copy_object(DestBucketName, DestKeyName, SrcBucketName, SrcKeyName, Options, Config) ->
    SrcVersion = case proplists:get_value(version_id, Options) of
                     undefined -> "";
                     VersionID -> ["?versionId=", VersionID]
                 end,
    RequestHeaders =
        [{"x-amz-copy-source", lists:flatten([SrcBucketName, $/, SrcKeyName, SrcVersion])},
         {"x-amz-metadata-directive",
          proplists:get_value(metadata_directive, Options)},
         {"x-amz-copy-source-if-match", proplists:get_value(if_match, Options)},
         {"x-amz-copy-source-if-none-match",
          proplists:get_value(if_none_match, Options)},
         {"x-amz-copy-source-if-unmodified-since",
          proplists:get_value(if_unmodified_since, Options)},
         {"x-amz-copy-source-if-modified-since",
          proplists:get_value(if_modified_since, Options)},
         {"x-amz-acl", encode_acl(proplists:get_value(acl, Options))}],
    {Headers, _Body} = s3_request(Config,
                                  put,
                                  DestBucketName,
                                  [$/|DestKeyName],
                                  "",
                                  [],
                                  [],
                                  RequestHeaders),
    [{copy_source_version_id,
      proplists:get_value("x-amz-copy-source-version-id", Headers, "false")},
     {version_id, proplists:get_value("x-amz-version-id", Headers, "null")}].

-spec create_bucket(string(), bucket_acl()|undefined, location_constraint()) ->
    ok.
create_bucket(BucketName, ACL, LocationConstraint) ->
    create_bucket(BucketName, ACL, LocationConstraint, default_config()).

-spec create_bucket(string(),
                    bucket_acl() | undefined,
                    location_constraint(),
                    config()) -> ok.
create_bucket(BucketName, ACL, LocationConstraint, Config) ->
    Headers = acl_to_headers(ACL),
    POSTData = location_constraint_to_post_data(LocationConstraint),
    s3_simple_request(Config, put, BucketName, "/", "", [], POSTData, Headers).

-spec acl_to_headers(bucket_acl() | undefined) ->
    [{string(), string() | undefined}].
acl_to_headers(private) ->
    [];
acl_to_headers(ACL) ->
    [{"x-amz-acl", encode_acl(ACL)}].

-spec location_constraint_to_post_data(location_constraint()) -> iolist().
location_constraint_to_post_data(none) ->
    [];
location_constraint_to_post_data(LocationConstraint) ->
    Location = encode_location_constraint(LocationConstraint),
    XML = {'CreateBucketConfiguration',
           [{xmlns, ?XMLNS_S3}],
           [{'LocationConstraint', Location}]},
    xmerl:export_simple([XML], xmerl_xml).

-spec encode_location_constraint(location_constraint()) -> string().
encode_location_constraint(eu) ->"EU";
encode_location_constraint(us_west_1) -> "us_west_1".

-spec encode_acl(bucket_acl() | undefined) -> string() | undefined.
encode_acl(undefined)                 -> undefined;
encode_acl(private)                   -> "private";
encode_acl(public_read)               -> "public-read";
encode_acl(public_read_write)         -> "public-read-write";
encode_acl(authenticated_read)        -> "authenticated-read";
encode_acl(bucket_owner_read)         -> "bucket-owner-read";
encode_acl(bucket_owner_full_control) -> "bucket-owner-full-control".

-spec delete_bucket(string()) -> ok.
delete_bucket(BucketName) ->
    delete_bucket(BucketName, default_config()).

-spec delete_bucket(string(), config()) -> ok.
delete_bucket(BucketName, Config) ->
    s3_simple_request(Config, delete, BucketName, "/", "", [], [], []).

-spec delete_object(string(), string()) -> proplists:proplist().
delete_object(BucketName, Key) ->
    delete_object(BucketName, Key, default_config()).

-spec delete_object(string(), string(), config()) -> proplists:proplist().
delete_object(BucketName, Key, Config) ->
    {Headers, _Body} = s3_request(Config, delete,
                                  BucketName, [$/|Key], "", [], [], []),
    Marker = proplists:get_value("x-amz-delete-marker", Headers, "false"),
    Id = proplists:get_value("x-amz-version-id", Headers, "null"),
    [{delete_marker, list_to_existing_atom(Marker)},
     {version_id, Id}].

-spec delete_object_version(string(), string(), string()) ->
    proplists:proplist().
delete_object_version(BucketName, Key, Version) ->
    delete_object_version(BucketName, Key, Version, default_config()).

-spec delete_object_version(string(), string(), string(), config()) ->
    proplists:proplist().
delete_object_version(BucketName, Key, Version, Config) ->
    {Headers, _Body} = s3_request(Config, delete, BucketName, [$/|Key],
                                  "versionId=" ++ Version, [], [], []),
    Marker = proplists:get_value("x-amz-delete-marker", Headers, "false"),
    Id = proplists:get_value("x-amz-version-id", Headers, "null"),
    [{delete_marker, list_to_existing_atom(Marker)},
     {version_id, Id}].

-spec list_buckets() -> proplists:proplist().
list_buckets() ->
    list_buckets(default_config()).

-spec list_buckets(config()) -> proplists:proplist().
list_buckets(Config) ->
    Doc = s3_xml_request(Config, get, "", "/", "", [], [], []),
    Buckets = [extract_bucket(Node)
               || Node <- xmerl_xpath:string("/*/Buckets/Bucket", Doc)],
    [{buckets, Buckets}].

-spec list_objects(string(), proplists:proplist()) -> proplists:proplist().
list_objects(BucketName, Options) ->
    list_objects(BucketName, Options, default_config()).

-spec list_objects(string(), proplists:proplist(), config()) ->
    proplists:proplist().
list_objects(BucketName, Options, Config) ->
    Params = [{"delimiter", proplists:get_value(delimiter, Options)},
              {"marker", proplists:get_value(marker, Options)},
              {"max-keys", proplists:get_value(max_keys, Options)},
              {"prefix", proplists:get_value(prefix, Options)}],
    Doc = s3_xml_request(Config, get, BucketName, "/", "", Params, [], []),
    Attributes = [{name, "Name", text},
                  {prefix, "Prefix", text},
                  {marker, "Marker", text},
                  {delimiter, "Delimiter", text},
                  {max_keys, "MaxKeys", integer},
                  {is_truncated, "IsTruncated", boolean},
                  {contents, "Contents", fun extract_contents/1}],
    ms3_xml:decode(Attributes, Doc).

extract_contents(Nodes) ->
    Attributes = [{key, "Key", text},
                  {last_modified, "LastModified", time},
                  {etag, "ETag", text},
                  {size, "Size", integer},
                  {storage_class, "StorageClass", text},
                  {owner, "Owner", fun extract_user/1}],
    [ms3_xml:decode(Attributes, Node) || Node <- Nodes].

extract_user([Node]) ->
    Attributes = [{id, "ID", text},
                  {display_name, "DisplayName", optional_text}],
    ms3_xml:decode(Attributes, Node).

-spec get_bucket_attribute(string(), settable_bucket_attribute_name()) -> term().
get_bucket_attribute(BucketName, AttributeName) ->
    get_bucket_attribute(BucketName, AttributeName, default_config()).

-spec get_bucket_attribute(string(), settable_bucket_attribute_name(), config()) ->
    term().
get_bucket_attribute(BucketName, AttributeName, Config) ->
    Attr = encode_attribute_name(AttributeName),
    Doc = s3_xml_request(Config, get, BucketName, "/", Attr, [], [], []),
    attribute_from_doc(AttributeName, Doc).

-spec attribute_from_doc(settable_bucket_attribute_name(), #xmlElement{}) -> any().
attribute_from_doc(acl, Doc) ->
    Attributes = [{owner, "Owner", fun extract_user/1},
                  {access_control_list,
                   "AccessControlList/Grant",
                    fun extract_acl/1
                  }],
    ms3_xml:decode(Attributes, Doc);
attribute_from_doc(location, Doc) ->
    ms3_xml:get_text("/LocationConstraint", Doc);
attribute_from_doc(logging, Doc) ->
    case xmerl_xpath:string("/BucketLoggingStatus/LoggingEnabled", Doc) of
        [] ->
            {enabled, false};
        [LoggingEnabled] ->
            Attributes = [{target_bucket, "TargetBucket", text},
                          {target_prefix, "TargetPrefix", text},
                          {target_trants,
                           "TargetGrants/Grant",
                           fun extract_acl/1
                          }],
            [{enabled, true} | ms3_xml:decode(Attributes, LoggingEnabled)]
    end;
attribute_from_doc(request_payment, Doc) ->
    case ms3_xml:get_text("/RequestPaymentConfiguration/Payer", Doc) of
        "Requester" -> requester;
        _           -> bucket_owner
    end;
attribute_from_doc(versioning, Doc) ->
    case ms3_xml:get_text("/VersioningConfiguration/Status", Doc) of
        "Enabled"   -> enabled;
        "Suspended" -> suspended;
        _           -> disabled
    end.

-spec encode_attribute_name(atom()) -> string().
encode_attribute_name(acl)             -> "acl";
encode_attribute_name(location)        -> "location";
encode_attribute_name(logging)         -> "logging";
encode_attribute_name(request_payment) -> "requestPayment";
encode_attribute_name(versioning)      -> "versioning".

extract_acl(ACL) ->
    [extract_grant(Item) || Item <- ACL].

% @TODO: Tighten up the grantee spec
-spec extract_grant(tuple()) -> [{grantee|permission,any()|permission()},...].
extract_grant(Node) ->
    [{grantee, extract_user(xmerl_xpath:string("Grantee", Node))},
     {permission, decode_permission(ms3_xml:get_text("Permission", Node))}].

-spec encode_permission(permission()) -> string().
encode_permission(full_control) -> "FULL_CONTROL";
encode_permission(write)        -> "WRITE";
encode_permission(write_acp)    -> "WRITE_ACP";
encode_permission(read)         -> "READ";
encode_permission(read_acp)     -> "READ_ACP".

-spec decode_permission(string()) -> permission().
decode_permission("FULL_CONTROL") -> full_control;
decode_permission("WRITE")        -> write;
decode_permission("WRITE_ACP")    -> write_acp;
decode_permission("READ")         -> read;
decode_permission("READ_ACP")     -> read_acp.

%% @doc Canonicalizes a proplist of {"Header", "Value"} pairs by
%% lower-casing all the Headers.
-spec canonicalize_headers(headers()) -> 
    [{LowerCaseHeader::string(), Value::string()}].
canonicalize_headers(Headers) ->
    [{string:to_lower(to_string(H)), V} || {H, V} <- Headers ].

-spec to_string(atom() | string()) -> string().
to_string(A) when is_atom(A) ->
    erlang:atom_to_list(A);
to_string(S) when is_list(S) ->
    S.

%% @doc Retrieves a value from a set of canonicalized headers.  The
%% given header should already be canonicalized (i.e., lower-cased).
%% Returns the value or the empty string if no such value was found.
-spec retrieve_header_value(Header::string(),
                            AllHeaders::[{Header::string(), Value::string()}]) ->
                                   string().
retrieve_header_value(Header, AllHeaders) ->
    proplists:get_value(Header, AllHeaders, "").

%% @doc Number of seconds since the Epoch that a request can be valid
%% for, specified by TimeToLive, which is the number of seconds from
%% "right now" that a request should be valid.
-spec expiration_time(TimeToLive::non_neg_integer()) ->
                             Expires::non_neg_integer().
expiration_time(TimeToLive) ->
    Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
    Now = calendar:datetime_to_gregorian_seconds(erlang:universaltime()),

    (Now - Epoch) + TimeToLive.

-spec if_not_empty(string(), iolist()) -> iolist().
if_not_empty("", _V) ->
    "";
if_not_empty(_, Value) ->
    Value.

-spec format_s3_uri(config(), string()) -> string().
format_s3_uri(#config{s3_url=S3Url, bucket_access_type=BAccessType}, Host) ->
    {ok,{Protocol,UserInfo,Domain,Port,_Uri,_QueryString}} =
        http_uri:parse(S3Url, [{ipv6_host_with_brackets, true}]),
    case BAccessType of
        virtual_hosted ->
            lists:flatten([erlang:atom_to_list(Protocol), "://",
                           if_not_empty(Host, [Host, $.]),
                           if_not_empty(UserInfo, [UserInfo, "@"]),
                           Domain, ":", erlang:integer_to_list(Port)]);
        path ->
            lists:flatten([erlang:atom_to_list(Protocol), "://",
                           if_not_empty(UserInfo, [UserInfo, "@"]),
                           Domain, ":", erlang:integer_to_list(Port),
                           if_not_empty(Host, [$/, Host])])
    end.



%% @doc Generate an S3 URL using Query String Request Authentication
%% (see
%% http://docs.amazonwebservices.com/AmazonS3/latest/dev/RESTAuthentication.html#RESTAuthenticationQueryStringAuth
%% for details).
%%
%% Note that this is **NOT** a complete implementation of the S3 Query
%% String Request Authentication signing protocol.  In particular, it
%% does nothing with "x-amz-*" headers, nothing for virtual hosted
%% buckets, and nothing for sub-resources.  It currently works for
%% relatively simple use cases (e.g., providing URLs to which
%% third-parties can upload specific files).
%%
%% Consult the official documentation (linked above) if you wish to
%% augment this function's capabilities.
-spec s3_url(atom(), string(), string(), integer(),
             proplists:proplist(), config()) -> binary().
s3_url(Method, BucketName, Key, Lifetime, RawHeaders,
       Config = #config{access_key_id=AccessKey,
                        secret_access_key=SecretKey})
  when is_list(BucketName), is_list(Key) ->

    Expires = erlang:integer_to_list(expiration_time(Lifetime)),

    Path = lists:flatten([$/, BucketName, $/ , Key]),
    CanonicalizedResource = ms3_http:url_encode_loose(Path),

    {_StringToSign, Signature} = make_signed_url_authorization(SecretKey, Method,
                                                               CanonicalizedResource,
                                                               Expires, RawHeaders),

    RequestURI = iolist_to_binary([
                                   format_s3_uri(Config, ""), CanonicalizedResource,
                                   $?, "AWSAccessKeyId=", AccessKey,
                                   $&, "Expires=", Expires,
                                   $&, "Signature=", ms3_http:url_encode_loose(Signature)
                                  ]),
    RequestURI.

make_signed_url_authorization(SecretKey, Method, CanonicalizedResource,
                              Expires, RawHeaders) ->
    Headers = canonicalize_headers(RawHeaders),

    HttpMethod = string:to_upper(atom_to_list(Method)),

    ContentType = retrieve_header_value("content-type", Headers),
    ContentMD5 = retrieve_header_value("content-md5", Headers),

    %% We don't currently use this, but I'm adding a placeholder for future enhancements See
    %% the URL in the docstring for details
    CanonicalizedAMZHeaders = "",


    StringToSign = lists:flatten([HttpMethod, $\n,
                                  ContentMD5, $\n,
                                  ContentType, $\n,
                                  Expires, $\n,
                                  CanonicalizedAMZHeaders, %% IMPORTANT: No newline here!!
                                  CanonicalizedResource
                                 ]),

    Signature = base64:encode(crypto:hmac(sha, SecretKey, StringToSign)),
    {StringToSign, Signature}.


-spec get_object(string(), string(), proplists:proplist()) ->
                        proplists:proplist().

get_object(BucketName, Key, Options) ->
    get_object(BucketName, Key, Options, default_config()).

-spec get_object(string(), string(), proplists:proplist(), config()) ->
                        proplists:proplist().

get_object(BucketName, Key, Options, Config) ->
    RequestHeaders = [{"Range", proplists:get_value(range, Options)},
                      {"If-Modified-Since", proplists:get_value(if_modified_since, Options)},
                      {"If-Unmodified-Since", proplists:get_value(if_unmodified_since, Options)},
                      {"If-Match", proplists:get_value(if_match, Options)},
                      {"If-None-Match", proplists:get_value(if_none_match, Options)}],
    Subresource = case proplists:get_value(version_id, Options) of
                      undefined -> "";
                      Version   -> ["versionId=", Version]
                  end,
    {Headers, Body} = s3_request(Config, get, BucketName, [$/|Key], Subresource, [], [], RequestHeaders),
    [{etag, proplists:get_value("etag", Headers)},
     {content_length, proplists:get_value("content-length", Headers)},
     {content_type, proplists:get_value("content-type", Headers)},
     {delete_marker, list_to_existing_atom(proplists:get_value("x-amz-delete-marker", Headers, "false"))},
     {version_id, proplists:get_value("x-amz-version-id", Headers, "null")},
     {content, Body}|
     extract_metadata(Headers)].

-spec get_object_acl(string(), string()) -> proplists:proplist().

get_object_acl(BucketName, Key) ->
    get_object_acl(BucketName, Key, default_config()).

-spec get_object_acl(string(), string(), proplists:proplist() | config()) -> proplists:proplist().

get_object_acl(BucketName, Key, Config)
  when is_record(Config, config) ->
    get_object_acl(BucketName, Key, [], Config);

get_object_acl(BucketName, Key, Options) ->
    get_object_acl(BucketName, Key, Options, default_config()).

-spec get_object_acl(string(), string(), proplists:proplist(), config()) -> proplists:proplist().
get_object_acl(BucketName, Key, Options, Config) ->
    Subresource = case proplists:get_value(version_id, Options) of
                      undefined -> "";
                      Version   -> ["&versionId=", Version]
                  end,
    Doc = s3_xml_request(Config, get, BucketName, [$/|Key], "acl" ++ Subresource, [], [], []),
    Attributes = [{owner, "Owner", fun extract_user/1},
                  {access_control_list, "AccessControlList/Grant", fun extract_acl/1}],
    ms3_xml:decode(Attributes, Doc).

-spec get_object_metadata(string(), string(), proplists:proplist()) -> proplists:proplist().

get_object_metadata(BucketName, Key, Options) ->
    get_object_metadata(BucketName, Key, Options, default_config()).

-spec get_object_metadata(string(), string(), proplists:proplist(), config()) -> proplists:proplist().

get_object_metadata(BucketName, Key, Options, Config) ->
    RequestHeaders = [{"If-Modified-Since", proplists:get_value(if_modified_since, Options)},
                      {"If-Unmodified-Since", proplists:get_value(if_unmodified_since, Options)},
                      {"If-Match", proplists:get_value(if_match, Options)},
                      {"If-None-Match", proplists:get_value(if_none_match, Options)}],
    Subresource = case proplists:get_value(version_id, Options) of
                      undefined -> "";
                      Version   -> ["versionId=", Version]
                  end,
    {Headers, _Body} = s3_request(Config, head, BucketName, [$/|Key], Subresource, [], [], RequestHeaders),
    [{last_modified, proplists:get_value("last-modified", Headers)},
     {etag, proplists:get_value("etag", Headers)},
     {content_length, proplists:get_value("content-length", Headers)},
     {content_type, proplists:get_value("content-type", Headers)},
     {delete_marker, list_to_existing_atom(proplists:get_value("x-amz-delete-marker", Headers, "false"))},
     {version_id, proplists:get_value("x-amz-version-id", Headers, "false")}|extract_metadata(Headers)].

extract_metadata(Headers) ->
    [{Key, Value} || {["x-amz-meta-"|Key], Value} <- Headers].

-spec get_object_torrent(string(), string()) -> proplists:proplist().

get_object_torrent(BucketName, Key) ->
    get_object_torrent(BucketName, Key, default_config()).

-spec get_object_torrent(string(), string(), config()) -> proplists:proplist().

get_object_torrent(BucketName, Key, Config) ->
    {Headers, Body} = s3_request(Config, get, BucketName, [$/|Key], "torrent", [], [], []),
    [{delete_marker, list_to_existing_atom(proplists:get_value("x-amz-delete-marker", Headers, "false"))},
     {version_id, proplists:get_value("x-amz-delete-marker", Headers, "false")},
     {torrent, Body}].

-spec list_object_versions(string(), proplists:proplist()) -> proplists:proplist().

list_object_versions(BucketName, Options) ->
    list_object_versions(BucketName, Options, default_config()).

-spec list_object_versions(string(), proplists:proplist(), config()) -> proplists:proplist().

list_object_versions(BucketName, Options, Config)
  when is_list(BucketName), is_list(Options) ->
    Params = [{"delimiter", proplists:get_value(delimiter, Options)},
              {"key-marker", proplists:get_value(key_marker, Options)},
              {"max-keys", proplists:get_value(max_keys, Options)},
              {"prefix", proplists:get_value(prefix, Options)},
              {"version-id-marker", proplists:get_value(version_id_marker, Options)}],
    Doc = s3_xml_request(Config, get, BucketName, "/", "versions", Params, [], []),
    Attributes = [{name, "Name", text},
                  {prefix, "Prefix", text},
                  {key_marker, "KeyMarker", text},
                  {next_key_marker, "NextKeyMarker", optional_text},
                  {version_id_marker, "VersionIdMarker", text},
                  {next_version_id_marker, "NextVersionIdMarker", optional_text},
                  {max_keys, "MaxKeys", integer},
                  {is_truncated, "Istruncated", boolean},
                  {versions, "Version", fun extract_versions/1},
                  {delete_markers, "DeleteMarker", fun extract_delete_markers/1}],
    ms3_xml:decode(Attributes, Doc).

extract_versions(Nodes) ->
    [extract_version(Node) || Node <- Nodes].

extract_version(Node) ->
    Attributes = [{key, "Key", text},
                  {version_id, "VersionId", text},
                  {is_latest, "IsLatest", boolean},
                  {etag, "ETag", text},
                  {size, "Size", integer},
                  {owner, "Owner", fun extract_user/1},
                  {storage_class, "StorageClass", text}],
    ms3_xml:decode(Attributes, Node).

extract_delete_markers(Nodes) ->
    [extract_delete_marker(Node) || Node <- Nodes].

extract_delete_marker(Node) ->
    Attributes = [{key, "Key", text},
                  {version_id, "VersionId", text},
                  {is_latest, "IsLatest", boolean},
                  {owner, "Owner", fun extract_user/1}],
    ms3_xml:decode(Attributes, Node).

extract_bucket(Node) ->
    ms3_xml:decode([{name, "Name", text},
                    {creation_date, "CreationDate", time}],
                   Node).

-spec put_object(string(),
                 string(),
                 iolist(),
                 proplists:proplist(),
                 [{string(), string()}]) -> [{'version_id', _}, ...].
put_object(BucketName, Key, Value, Options, HTTPHeaders) ->
    put_object(BucketName, Key, Value, Options, HTTPHeaders, default_config()).

-spec put_object(string(),
                 string(),
                 iolist(),
                 proplists:proplist(),
                 [{string(), string()}],
                 config()) -> [{'version_id', _}, ...].
put_object(BucketName, Key, Value, Options, HTTPHeaders, Config)
  when is_list(BucketName), is_list(Key), is_list(Value) orelse is_binary(Value),
       is_list(Options) ->
    RequestHeaders = [{"x-amz-acl", encode_acl(proplists:get_value(acl, Options))}|HTTPHeaders]
        ++ [{["x-amz-meta-"|string:to_lower(MKey)], MValue} ||
               {MKey, MValue} <- proplists:get_value(meta, Options, [])],
    ContentType = proplists:get_value("content-type", HTTPHeaders, "application/octet_stream"),
    POSTData = {Value, ContentType},
    {Headers, _Body} = s3_request(Config, put, BucketName, [$/|Key], "", [],
                                  POSTData, RequestHeaders),
    [{version_id, proplists:get_value("x-amz-version-id", Headers, "null")}].

-spec set_object_acl(string(), string(), proplists:proplist()) -> ok.

set_object_acl(BucketName, Key, ACL) ->
    set_object_acl(BucketName, Key, ACL, default_config()).

-spec set_object_acl(string(), string(), proplists:proplist(), config()) -> ok.

set_object_acl(BucketName, Key, ACL, Config)
  when is_list(BucketName), is_list(Key), is_list(ACL) ->
    Id = proplists:get_value(id, proplists:get_value(owner, ACL)),
    DisplayName = proplists:get_value(display_name, proplists:get_value(owner, ACL)),
    ACL1 = proplists:get_value(access_control_list, ACL),
    XML = {'AccessControlPolicy',
           [{'Owner', [{'ID', [Id]}, {'DisplayName', [DisplayName]}]},
            {'AccessControlList', encode_grants(ACL1)}]},
    XMLText = list_to_binary(xmerl:export_simple([XML], xmerl_xml)),
    s3_simple_request(Config, put, BucketName, [$/|Key], "acl", [], XMLText, []).

-spec set_bucket_attribute(string(),
                           settable_bucket_attribute_name(),
                           'bucket_owner' | 'requester' | [any()]) -> ok.

set_bucket_attribute(BucketName, AttributeName, Value) ->
    set_bucket_attribute(BucketName, AttributeName, Value, default_config()).

-spec set_bucket_attribute(string(), settable_bucket_attribute_name(),
                           'bucket_owner' | 'requester' | [any()], config()) -> ok.

set_bucket_attribute(BucketName, AttributeName, Value, Config)
  when is_list(BucketName) ->
    {Subresource, XML} =
        case AttributeName of
            acl ->
                ACLXML = {'AccessControlPolicy',
                          [{'Owner',
                            [{'ID', [proplists:get_value(id, proplists:get_value(owner, Value))]},
                             {'DisplayName', [proplists:get_value(display_name, proplists:get_value(owner, Value))]}]},
                           {'AccessControlList', encode_grants(proplists:get_value(access_control_list, Value))}]},
                {"acl", ACLXML};
            logging ->
                LoggingXML = {'BucketLoggingStatus',
                              [{xmlns, ?XMLNS_S3}],
                              case proplists:get_bool(enabled, Value) of
                                  true ->
                                      [{'LoggingEnabled',
                                        [
                                         {'TargetBucket', [proplists:get_value(target_bucket, Value)]},
                                         {'TargetPrefix', [proplists:get_value(target_prefix, Value)]},
                                         {'TargetGrants', encode_grants(proplists:get_value(target_grants, Value, []))}
                                        ]
                                       }];
                                  false ->
                                      []
                              end},
                {"logging", LoggingXML};
            request_payment ->
                PayerName = case Value of
                                requester -> "Requester";
                                bucket_owner -> "BucketOwner"
                            end,
                RPXML = {'RequestPaymentConfiguration', [{xmlns, ?XMLNS_S3}],
                         [
                          {'Payer', [PayerName]}
                         ]
                        },
                {"requestPayment", RPXML};
            versioning ->
                Status = case proplists:get_value(status, Value) of
                             suspended -> "Suspended";
                             enabled -> "Enabled"
                         end,
                MFADelete = case proplists:get_value(mfa_delete, Value, disabled) of
                                enabled -> "Enabled";
                                disabled -> "Disabled"
                            end,
                VersioningXML = {'VersioningConfiguration', [{xmlns, ?XMLNS_S3}],
                                 [{'Status', [Status]},
                                  {'MfaDelete', [MFADelete]}]},
                {"versioning", VersioningXML}
        end,
    POSTData = list_to_binary(xmerl:export_simple([XML], xmerl_xml)),
    Headers = [{"content-type", "application/xml"}],
    s3_simple_request(Config, put, BucketName, "/", Subresource, [], POSTData, Headers).

encode_grants(Grants) ->
    [encode_grant(Grant) || Grant <- Grants].

encode_grant(Grant) ->
    Grantee = proplists:get_value(grantee, Grant),
    {'Grant',
     [{'Grantee', [{xmlns, ?XMLNS_S3}],
       [{'ID', [proplists:get_value(id, proplists:get_value(owner, Grantee))]},
        {'DisplayName', [proplists:get_value(display_name, proplists:get_value(owner, Grantee))]}]},
      {'Permission', [encode_permission(proplists:get_value(permission, Grant))]}]}.

-spec s3_simple_request(config(), method(), string(), string(), string(), list(), post_data(), headers()) -> ok.
s3_simple_request(Config, Method, Host, Path, Subresource, Params, POSTData, Headers) ->
    case s3_request(Config, Method, Host, Path,
                    Subresource, Params, POSTData, Headers) of
        {_Headers, <<>>} ->
            ok;
        {_Headers, Body} ->
            XML = element(1,xmerl_scan:string(binary_to_list(Body))),
            case XML of
                #xmlElement{name='Error'} ->
                    ErrCode = ms3_xml:get_text("/Error/Code", XML),
                    ErrMsg = ms3_xml:get_text("/Error/Message", XML),
                    erlang:error({s3_error, ErrCode, ErrMsg});
                _ ->
                    ok
            end
    end.

s3_xml_request(Config, Method, Host, Path, Subresource, Params, POSTData, Headers) ->
    {_Headers, Body} = s3_request(Config, Method, Host, Path,
                                  Subresource, Params, POSTData, Headers),
    XML = element(1,xmerl_scan:string(binary_to_list(Body))),
    case XML of
        #xmlElement{name='Error'} ->
            ErrCode = ms3_xml:get_text("/Error/Code", XML),
            ErrMsg = ms3_xml:get_text("/Error/Message", XML),
            erlang:error({s3_error, ErrCode, ErrMsg});
        _ ->
            XML
    end.

-spec get_credentials_iam_role() -> binary().
get_credentials_iam_role() ->
    URI = ?AMAZON_METADATA_SERVICE ++ "iam/security-credentials/",
    Resp = send_req(URI, "GET"),
    case Resp of
        {ok, {{200, _}, _Headers, CredentialsIamRole}} ->
            CredentialsIamRole;
        {ok, {{_, Reason}, _Headers, _Body}} ->
            erlang:error({iam_error, Reason,
                          "Failed to retrieve Amazon IAM Role"})
    end.

-spec get_credentials(baked_in|iam, headers(), string(), string()) ->
    {headers(), binary(), binary()}.
get_credentials(baked_in, Headers, AccessKey, SecretKey) ->
    {Headers, AccessKey, SecretKey};
get_credentials(iam, InitialHeaders, _, _) ->
    CredentialsIamRole = binary_to_list(get_credentials_iam_role()),
    URI = ?AMAZON_METADATA_SERVICE ++ "iam/security-credentials/" ++ CredentialsIamRole,
    Resp = send_req(URI, get),
    case Resp of
        {ok, {{200, _Reason}, _Headers, JSONBody}} ->
            IAMData = jsx:decode(JSONBody),
            AccessKeyBin = proplists:get_value(<<"AccessKeyId">>, IAMData),
            SecretAccessKeyBin = proplists:get_value(<<"SecretAccessKey">>, IAMData),
            SecurityToken = proplists:get_value(<<"Token">>, IAMData),
            Headers = [{"x-amz-security-token", SecurityToken} | InitialHeaders],
            {Headers, AccessKeyBin, SecretAccessKeyBin};
        {ok, {{StatusCode, Reason}, _Headers, _Body}} ->
            ErrorMsg = integer_to_list(StatusCode) ++ Reason,
            erlang:error({iam_error,
                          ErrorMsg,
                          "Failed to retrieve Amazon IAM Credentials"})
    end.

%% @TODO: Remove this binary() -> iolist() code and use iolist() throughout
-spec s3_request(config(), method(), string(), string(), string(), list(), post_data(), headers()) -> {headers(), binary()}.
s3_request(Config,Method,Host,Path,Sub,Params,POSTData,InitialHeaders)
    when is_binary(POSTData) ->
    s3_request(Config,Method,Host,Path,Sub,Params,[POSTData],InitialHeaders);
s3_request(Config, Method, Host, Path, Sub, Params, {D, C}, InitialHeaders)
    when is_binary(D) ->
    s3_request(Config,Method,Host,Path,Sub,Params,{[D], C},InitialHeaders);
s3_request(Config = #config{credentials_store=CredentialsStore,
                            access_key_id=MaybeAccessKey,
                            secret_access_key=MaybeSecretKey},
           Method, Host, Path, Subresource, Params, POSTData, InitialHeaders) ->
    {Headers, AccessKey, SecretKey} =
        get_credentials(CredentialsStore, InitialHeaders,
                        MaybeAccessKey, MaybeSecretKey),
    {ContentMD5, ContentType, Body} =
        case POSTData of
            {PD, CT} ->
                {base64:encode(crypto:hash(md5, PD)), CT, PD};
            PD ->
                %% On a put/post even with an empty body we need to
                %% default to some content-type
                case Method of
                    _ when put == Method; post == Method ->
                        {"", "text/xml", PD};
                    _ ->
                        {"", "", PD}
                end
        end,
    AmzHeaders = lists:filter(fun ({"x-amz-" ++ _, V}) when
                                        V =/= undefined -> true;
                                  (_) -> false
                              end, Headers),
    Date = httpd_util:rfc1123_date(erlang:localtime()),
    EscapedPath = ms3_http:url_encode_loose(Path),
    {_StringToSign, Authorization} =
        make_authorization(AccessKey, SecretKey, Method,
                           ContentMD5, ContentType,
                           Date, AmzHeaders, Host,
                           EscapedPath, Subresource),
    FHeaders = [Header || {_, Value} = Header <- Headers, Value =/= undefined],
    RequestHeaders0 = [{"date", Date}, {"authorization", Authorization}|FHeaders] ++
        case ContentMD5 of
            "" -> [];
            _  -> [{"content-md5", binary_to_list(ContentMD5)}]
        end,
    RequestHeaders1 = case proplists:is_defined("content-type", RequestHeaders0) of
                          true ->
                              RequestHeaders0;
                          false ->
[{"content-type", ContentType} | RequestHeaders0]
                      end,
    RequestURI = lists:flatten([format_s3_uri(Config, Host),
                                EscapedPath,
                                if_not_empty(Subresource, [$?, Subresource]),
                                if
                                    Params =:= [] -> "";
                                    Subresource =:= "" -> [$?, ms3_http:make_query_string(Params)];
                                    true -> [$&, ms3_http:make_query_string(Params)]
                                end]),
    send_s3_request(RequestURI, Method, RequestHeaders1, Body).

-spec send_s3_request(string(), atom(), headers(), iodata()) ->
    {headers(), binary()}.
send_s3_request(URI, Method, Headers, Body) ->
    Response = case Method of
        get ->
            send_req(URI, "GET", Headers);
        delete ->
            send_req(URI, "DELETE", Headers);
        head ->
            %% ibrowse is unable to handle HEAD request responses that are sent
            %% with chunked transfer-encoding (why servers do this is not
            %% clear). While we await a fix in ibrowse, forcing the HEAD request
            %% to use HTTP 1.0 works around the problem.
            %%
            %% @TODO: Verify this against live Amazon S3 using lhttpc
            send_req(URI, "HEAD", Headers);
        %% @TODO: I think this is 'put' only. Let's make it explicit
        _ ->
            send_req(URI, Method, Headers, Body)
    end,
    parse_s3_response(Response).
    
-spec parse_s3_response(response()) -> {headers(), binary()}.
parse_s3_response({error, Error}) ->
    erlang:error({aws_error, {socket_error, Error}});
parse_s3_response({ok, {{StatusCode, _Reason}, Headers, Body}}) ->
    Headers1 = canonicalize_headers(Headers),
    case StatusCode >= 200 andalso StatusCode =< 299 of
        true ->
            {Headers1, Body};
        false ->
            erlang:error({aws_error, {http_error, StatusCode, {Headers,Body}}})
    end.

-spec send_req(string(), method() | string()) -> response().
send_req(Uri, Method) ->
    send_req(Uri, Method, [], []).

-spec send_req(string(), method() | string(), headers()) -> response().
send_req(Uri, Method, Headers) ->
    send_req(Uri, Method, Headers, []).

-spec send_req(string(), method()|string(), headers(), iolist()) -> response().
send_req(Uri, Method, Headers, Body) ->
    lhttpc:request(Uri, Method, Headers, Body, ?DEFAULT_HTTP_TIMEOUT).

make_authorization(AccessKeyId, SecretKey, Method, ContentMD5, ContentType, Date, AmzHeaders, Host, Resource, Subresource) ->
    CanonizedAmzHeaders =
        [[Name, $:, Value, $\n] || {Name, Value} <- lists:sort(AmzHeaders)],
    StringToSign = [string:to_upper(atom_to_list(Method)), $\n,
                    ContentMD5, $\n,
                    ContentType, $\n,
                    Date, $\n,
                    CanonizedAmzHeaders,
                    if_not_empty(Host, [$/, Host]),
                    Resource,
                    if_not_empty(Subresource, [$?, Subresource])],
    ShaHmac = crypto:hmac(sha, SecretKey, StringToSign),
    Signature = base64:encode_to_string(ShaHmac),
    {StringToSign, lists:flatten(["AWS ", AccessKeyId, $:, Signature])}.

-spec default_config() -> config().
default_config() ->
    Defaults =  envy:get(mini_s3, s3_defaults, list),
    case proplists:is_defined(key_id, Defaults) andalso
        proplists:is_defined(secret_access_key, Defaults) of
        true ->
            {key_id, Key} = proplists:lookup(key_id, Defaults),
            {secret_access_key, AccessKey} =
                proplists:lookup(secret_access_key, Defaults),
            #config{access_key_id=Key, secret_access_key=AccessKey};
        false ->
            throw({error, missing_s3_defaults})
    end.


-ifdef(TEST).
format_s3_uri_test_() ->
    Config = fun(Url, Type) ->
                     #config{s3_url = Url, bucket_access_type = Type}
             end,
    Tests = [
             %% hostname
             {"https://my-aws.me.com", virtual_hosted, "https://bucket.my-aws.me.com:443"},
             {"https://my-aws.me.com", path, "https://my-aws.me.com:443/bucket"},

             %% ipv4
             {"https://192.168.12.13", path, "https://192.168.12.13:443/bucket"},

             %% ipv6
             {"https://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]", path,
              "https://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]:443/bucket"},

             %% These tests document current behavior. Using
             %% virtual_hosted with an IP address does not make sense,
             %% but leaving as-is for now to avoid adding the
             %% is_it_an_ip_or_a_name code.
             {"https://192.168.12.13", virtual_hosted, "https://bucket.192.168.12.13:443"},

             {"https://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]", virtual_hosted,
              "https://bucket.[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]:443"}
            ],
    [ ?_assertEqual(Expect, format_s3_uri(Config(Url, Type), "bucket"))
      || {Url, Type, Expect} <- Tests ].
-endif.
