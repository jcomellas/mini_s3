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
         make_signed_url_authorization/5,
         service_and_location_to_endpoint/2,
         base64_hash_file/3]).

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
              location_constraint/0,
              service/0,
              headers/0,
              canonical_headers/0,
              method/0,
              http_response/0,
              httpc_opts/0]).

-opaque config() :: record(config).

-type datetime() :: calendar:date() | calendar:datetime().

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
                             | 'us-west-1'
                             | 'us-west-2'
                             | 'eu-west-1'
                             | 'ap-southeast-1'
                             | 'ap-southeast-2'
                             | 'ap-northeast-1'
                             | 'sa-east-1'.

-type permission() :: full_control
                    | write
                    | write_acp
                    | read
                    | read_acp.

-type header()  :: {string(), any() | undefined}.

-type headers() :: [header()].

-type canonical_headers() :: [{string(), string()}].

-type http_response() :: {ok, {pos_integer(), headers(), binary()}}
                       | {error, any()}.

-type post_data() :: {iodata(), string()} | iodata().

-type method() :: get | head | post | put | delete | trace | 
                 options | connect | patch.

-type service() :: iam | s3.

-type chunk_size_bytes() :: pos_integer().

-type put_object() :: iolist() 
                    | {stream_from, filename()}
                    | {stream_from, filename(), chunk_size_bytes()}.

-type hash() :: string().

-type filename() :: file:filename().

-type etag() :: string().

-type range() :: {Start::integer(), End::integer()}.

-type partial_download_opt() :: {partial_download,
                                 [{window_size, infinity | pos_integer()}
                                | {part_size, pos_integer()}
                                 ]
                                }.
-type stream_to_file_opt() :: {stream_to_file, file:filename()}
                            | {stream_to_file,{file:filename(), pos_integer()}}.

-type get_object_option() :: {range, range() | string()}
                           | {if_modified_since, datetime()}
                           | {if_unmodified_since, datetime()}
                           | {if_match, etag()}
                           | {if_none_match, etag()}
                           | {version_id, string()}
                           | stream_to_file_opt()
                           | partial_download_opt()
                           | lhttpc_opt().

-type get_object_options() :: [get_object_option()].

-type copy_object_option()  :: {version_id, string()}
                             | {metadata_directive, string()}
                             | {if_match, etag()}
                             | {if_none_match, etag()}
                             | {if_unmodified_since, string()}
                             | {if_modified_since, string()}
                             | {acl, string()}
                             | lhttpc_opt().

-type copy_object_options() :: [copy_object_option()].

-type list_objects_option() :: {delimiter, string()}
                             | {marker, string()}
                             | {max_keys, string()}
                             | {prefix, string()}
                             | lhttpc_opt().

-type list_objects_options() :: [list_objects_option()].

-type put_object_option() :: {meta, [{Key::string(), Value::string()}]}
                           | {acl, string()}
                           | {send_retry, pos_integer()}
                           | lhttpc_opt().

-type put_object_options() :: [put_object_option()].

-type list_object_versions_option() :: {delimiter, string()}
                                     | {key_marker, string()}
                                     | {max_keys, string()}
                                     | {prefix, string()}
                                     | {version_id_marker, string()}
                                     | lhttpc_opt().

-type list_object_versions_options() :: [list_object_versions_option()].

-type get_object_metadata_option() :: {if_modified_since, datetime()}
                                    | {if_unmodified_since, datetime()}
                                    | {if_match, etag()}
                                    | {if_none_match, etag()}
                                    | {version_id, string()}
                                    | lhttpc_opt().

-type get_object_metadata_options() :: [get_object_metadata_option()].

-type get_object_acl_options() :: [{version_id, string()}].

-type httpc_opt() :: {timeout, pos_integer()}.

-type httpc_opts() :: [httpc_opt()].

-type lhttpc_opt() :: {connect_timeout, pos_integer() | infinity}
                    | {connect_options, [ssl:ssloption() | gen_tcp:option()]}
                    | {proxy, httpc:url()}
                    | {proxy_ssl_options, [ssl:ssloption()]}.

-record(chunk_state, {filename = ""                    :: string(),
                      file                             :: file:file()|undefined,
                      position = 0                     :: non_neg_integer(),
                      chunk_size = ?DEFAULT_CHUNK_SIZE :: pos_integer()}).

%% This is a helper function that exists to make development just a
%% wee bit easier
%% TODO: move this to CT tests
-spec manual_start() -> ok.
manual_start() ->
    ok = application:start(asn1),
    ok = application:start(crypto),
    ok = application:start(public_key),
    ok = application:start(ssl),
    ok = application:start(inets),
    httpc_impl:start().

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

-spec copy_object(string(),
                  string(),
                  string(),
                  string(),
                  copy_object_options()) -> proplists:proplist().
copy_object(DestBucketName, DestKeyName, SrcBucketName, SrcKeyName, Options) ->
    copy_object(DestBucketName, DestKeyName, SrcBucketName,
                SrcKeyName, Options, default_config()).

-spec copy_object(string(),
                  string(),
                  string(),
                  string(),
                  copy_object_options(),
                  config()) -> proplists:proplist().
copy_object(DestBucketName,DestKeyName,SrcBucketName,SrcKeyName,Opts,Config) ->
    SrcVersion = case get_value(version_id, Opts) of
                     undefined -> "";
                     VersionID -> ["?versionId=", VersionID]
                 end,
    ReqHdrs = make_copy_headers(SrcBucketName, SrcKeyName, SrcVersion, Opts),
    R = s3_request(Config,put,DestBucketName,[$/|DestKeyName],"",[],[],ReqHdrs),
    {RespHdrs, _Body} = R,
    [
     {copy_source_version_id,
      get_value("x-amz-copy-source-version-id", RespHdrs, "false")},
     {version_id, get_value("x-amz-version-id", RespHdrs, "null")}
    ].

-spec create_bucket(string(), bucket_acl()|undefined, location_constraint()) ->
    ok.
create_bucket(BucketName, ACL, LocationConstraint) ->
    create_bucket(BucketName, ACL, LocationConstraint, default_config()).

-spec create_bucket(string(),
                    bucket_acl() | undefined,
                    location_constraint(),
                    config()) -> ok.
create_bucket(BucketName, ACL, LocationConstraint, Config) ->
    Hdrs = case ACL of
        private -> [];
        _       -> [acl_header(ACL)]
    end,
    Data = location_constraint_to_post_data(LocationConstraint),
    s3_simple_request(Config, put, BucketName, "/", "", [], Data, Hdrs).

-spec acl_header(bucket_acl() | undefined) ->
    {string(), string() | undefined}.
acl_header(ACL) ->
    {"x-amz-acl", encode_acl(ACL)}.

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
encode_location_constraint(Constraint) -> atom_to_list(Constraint).
location_constraint_to_endpoint('us-east-1') ->
    "s3.amazonaws.com ";
location_constraint_to_endpoint(Constraint) ->
    "s3-" ++ encode_location_constraint(Constraint) ++ ".amazonaws.com".

%% @doc Generates an HTTPS endpoint to an Amazon Web Service from the
%%      service type (S3, IAM, etc.) and the location constraint.
%%
%%      e.g. S3 + 'us-west-2' = "https://s3-us-west-2.amazonaws.com"
-spec service_and_location_to_endpoint(service(), location_constraint()) ->
    string().
service_and_location_to_endpoint(Service, Location) ->
    service_and_location_to_endpoint(Service, Location, true).

-spec service_and_location_to_endpoint(service(),
                                       location_constraint(),
                                       Secure::boolean()) ->
    string().
service_and_location_to_endpoint(iam, _, true) ->
    "https://iam.amazonaws.com";
service_and_location_to_endpoint(s3, Location, true) ->
    "https://" ++ location_constraint_to_endpoint(Location);
service_and_location_to_endpoint(s3, Location, false) ->
    "http://" ++ location_constraint_to_endpoint(Location).

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
    Marker = get_value("x-amz-delete-marker", Headers, "false"),
    Id = get_value("x-amz-version-id", Headers, "null"),
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
    Marker = get_value("x-amz-delete-marker", Headers, "false"),
    Id = get_value("x-amz-version-id", Headers, "null"),
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

-spec list_objects(string(), list_objects_options(), config()) ->
    proplists:proplist().
list_objects(BucketName, Options, Config) ->
    Params = [{"delimiter", get_value(delimiter, Options)},
              {"marker", get_value(marker, Options)},
              {"max-keys", get_value(max_keys, Options)},
              {"prefix", get_value(prefix, Options)}],
    Doc = s3_xml_request(Config, get, BucketName, "/", "", Params, [], []),
    Attributes = [{name, "Name", text},
                  {prefix, "Prefix", text},
                  {marker, "Marker", text},
                  {delimiter, "Delimiter", text},
                  {max_keys, "MaxKeys", integer},
                  {is_truncated, "IsTruncated", boolean},
                  {contents, "Contents", fun extract_contents/1}],
    ms3_xml:decode(Attributes, Doc).

make_copy_headers(BucketName, KeyName, Version, Opts)->
    [{"x-amz-copy-source", lists:flatten([BucketName, $/, KeyName, Version])},
     {"x-amz-metadata-directive", get_value(metadata_directive, Opts)},
     {"x-amz-copy-source-if-match", get_value(if_match, Opts)},
     {"x-amz-copy-source-if-none-match",get_value(if_none_match, Opts)},
     {"x-amz-copy-source-if-unmodified-since",
      get_value(if_unmodified_since, Opts)},
     {"x-amz-copy-source-if-modified-since",get_value(if_modified_since, Opts)},
     {"x-amz-acl", encode_acl(get_value(acl, Opts))}].

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

-spec get_bucket_attribute(string(), settable_bucket_attribute_name()) -> 
    term().
get_bucket_attribute(BucketName, AttributeName) ->
    get_bucket_attribute(BucketName, AttributeName, default_config()).

-spec get_bucket_attribute(string(),settable_bucket_attribute_name(),config())->
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
-spec canonicalize_headers(headers()) -> canonical_headers().
canonicalize_headers(Headers) ->
    [{string:to_lower(to_string(H)), V} || {H, V} <- Headers ].

-spec to_string(atom() | string() | binary() | range()) -> string().
to_string(A) when is_atom(A) ->
    erlang:atom_to_list(A);
to_string(B) when is_binary(B) ->
    erlang:binary_to_list(B);
to_string(S) when is_list(S) ->
    S;
to_string({range, Start, End}) when is_integer(Start), is_integer(End) ->
    "bytes="++integer_to_list(Start)++"-"++integer_to_list(End);
to_string({range, Start, End})  when is_list(Start), is_list(End) ->
    "bytes="++Start++"-"++End;
to_string({Y, M, D})  when is_integer(Y), is_integer(M), is_integer(D) ->
    httpd_util:rfc1123_date({{Y, M, D},{0, 0, 0}});
to_string({{Y, M, D}, {H, Min, S}})  when is_integer(Y),
                                          is_integer(M),
                                          is_integer(D),
                                          is_integer(H),
                                          is_integer(Min),
                                          is_integer(S) ->
    httpd_util:rfc1123_date({{Y, M, D}, {H, Min, S}}).

%% @doc Retrieves a value from a set of canonicalized headers.  The
%% given header should already be canonicalized (i.e., lower-cased).
%% Returns the value or the empty string if no such value was found.
-spec retrieve_header_value(string(), canonical_headers()) ->
                                   string().
retrieve_header_value(Header, AllHeaders) ->
    get_value(Header, AllHeaders, "").

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
    {ok,{Protocol,UserInfo,Domain,Port,_URI,_QueryString}} =
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
s3_url(Method, BucketName, Key, Lifetime, RawHeaders,Config) ->
    #config{access_key_id=AccessKey,secret_access_key=SecretKey} = Config,
    Expires = integer_to_list(expiration_time(Lifetime)),
    Path = lists:flatten([$/, BucketName, $/ , Key]),
    CanonicalizedResource = ms3_http:url_encode_loose(Path),
    {_, Signature} = make_signed_url_authorization(SecretKey,
                                                   Method,
                                                   CanonicalizedResource,
                                                   Expires,
                                                   RawHeaders),
    RequestURI = iolist_to_binary([format_s3_uri(Config, ""), 
                                   CanonicalizedResource,
                                   $?, "AWSAccessKeyId=", AccessKey,
                                   $&, "Expires=", Expires,
                                   $&, "Signature=",
                                   ms3_http:url_encode_loose(Signature)
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


-spec get_object(string(), string(), get_object_options()) ->
                        proplists:proplist().
get_object(BucketName, Key, Options) ->
    get_object(BucketName, Key, Options, default_config()).

-spec get_object(string(), string(), get_object_options(), config()) ->
                        proplists:proplist().
get_object(Bucket, Key, Opts, Config) ->
    {Hdrs, Opts1} = opts_to_headers(Opts, [], []),
    Sub = case get_value(version_id, Opts) of
              undefined -> "";
              Version   -> ["versionId=", Version]
    end,
    case get_value(stream_to_file, Opts) of 
        undefined ->
            R = s3_request(Config,get,Bucket,[$/|Key],Sub,[],[],Hdrs,Opts1),
            {RespHdrs, Content} = R,
            [{content, Content} | response_hdrs_to_proplist(RespHdrs, [])];
        {Filename, ChnkSz} ->
            get_chunks(Config, Bucket, Key, Sub, Hdrs, Opts1, Filename, ChnkSz);
        Filename ->
            ChnkSz = ?DEFAULT_CHUNK_SIZE,
            get_chunks(Config, Bucket, Key, Sub, Hdrs, Opts1, Filename, ChnkSz)
    end.

%% This handles downloading a file in chunks of `ChnkSz` bytes. It uses the
%% `Byte-Range` header to pull down `ChnkSz` bytes at a time.
-spec get_chunks(any(),
                 string(),
                 string(),
                 string(),
                 headers(),
                 get_object_options(),
                 file:filename(),
                 non_neg_integer()) ->
    proplists:proplist().
get_chunks(Conf, Bucket, Key, Sub, Hdrs, Opts, Filename, ChnkSz) ->
    {ok, File} = file:open(Filename, [binary, write, raw]),
    Opts1 = lists:keydelete(stream_to_file, 1, Opts),
    State = #chunk_state{filename  = Filename,
                         file      = File,
                         position  = 0,
                         chunk_size = ChnkSz},    
    get_chunks1(Conf, Bucket, Key, Sub, Hdrs, Opts1, State).

get_chunks1(Config, Bucket, Key, Sub, Hdrs, Opts, State) ->
    #chunk_state{position=Pos,
                 chunk_size=ChnkSz,
                 file=File,
                 filename=Filename} = State,
    %% for a 50 byte chunk size, the initial range is 0 - 49 since
    %% HTTP byte ranges are inclusive
    Opts1 = lists:keystore(range, 1, Opts, {range, {Pos, Pos + ChnkSz - 1}}),
    Result = get_object(Bucket, Key, Opts1, Config),
    Content = get_value(content, Result),
    ok = file:write(File, Content),
    CL = list_to_integer(get_value(content_length, Result)),
    case CL =< ChnkSz of
        true ->
            ok = file:close(File),
            make_chunk_result(Result, Filename);
        false ->
            State1 = State#chunk_state{position = Pos + ChnkSz},
            get_chunks1(Config, Bucket, Key, Sub, Hdrs, Opts, State1)
    end.

-spec make_chunk_result(proplists:proplist(), file:filename()) ->
    proplists:proplist().
make_chunk_result(Result, Filename) ->
    Result1 = lists:keydelete(content, 1, Result),
    [{filename, Filename} | Result1].

-spec get_object_acl(string(), string()) -> proplists:proplist().
get_object_acl(BucketName, Key) ->
    get_object_acl(BucketName, Key, default_config()).

-spec get_object_acl(string(), string(), get_object_acl_options() | config()) ->
    proplists:proplist().
get_object_acl(BucketName, Key, Options) when is_list(Options)->
    get_object_acl(BucketName, Key, Options, default_config());
get_object_acl(BucketName, Key, Config) ->
    get_object_acl(BucketName, Key, [], Config).

-spec get_object_acl(string(), string(), get_object_acl_options(), config()) -> proplists:proplist().
get_object_acl(BucketName, Key, Options, Config) ->
    Subresource = case get_value(version_id, Options) of
                      undefined -> "";
                      Version   -> ["&versionId=", Version]
                  end,
    Doc = s3_xml_request(Config, get, BucketName, [$/|Key], "acl" ++ Subresource, [], [], []),
    Attributes = [{owner, "Owner", fun extract_user/1},
                  {access_control_list, "AccessControlList/Grant", fun extract_acl/1}],
    ms3_xml:decode(Attributes, Doc).

-spec get_object_metadata(string(), string(), get_object_metadata_options()) ->
    proplists:proplist().
get_object_metadata(BucketName, Key, Options) ->
    get_object_metadata(BucketName, Key, Options, default_config()).

-spec get_object_metadata(string(),
                          string(),
                          get_object_metadata_options(),
                          config()) -> proplists:proplist().
get_object_metadata(Bucket, Key, Opts, Conf) ->
    {Hdrs, Opts1} = opts_to_headers(Opts, [], []), 
    Sub = case get_value(version_id, Opts) of
        undefined -> "";
        Version   -> ["versionId=", Version]
    end,
    {Headers,_} = s3_request(Conf,head,Bucket,[$/|Key],Sub,[],[],Hdrs,Opts1),
    response_hdrs_to_proplist(Headers, []).

response_hdrs_to_proplist([], Acc) ->
    Acc1 = case lists:keyfind(delete_marker, 1, Acc) of
        false -> [{delete_marker, false} | Acc];
        _     -> Acc
    end,
    case lists:keyfind(version_id, 1, Acc1) of
        false -> [{version_id, false} | Acc1];
        _     -> Acc1
    end;
response_hdrs_to_proplist([{"last-modified", Value} |Rest], Acc) ->
    response_hdrs_to_proplist(Rest, [{last_modified, Value} | Acc]);
response_hdrs_to_proplist([{"etag", Value} |Rest], Acc) ->
    response_hdrs_to_proplist(Rest, [{etag, Value} | Acc]);
response_hdrs_to_proplist([{"content-length", Value} |Rest], Acc) ->
    response_hdrs_to_proplist(Rest, [{content_length, Value} | Acc]);
response_hdrs_to_proplist([{"content-type", Value} |Rest], Acc) ->
    response_hdrs_to_proplist(Rest, [{content_type, Value} | Acc]);
response_hdrs_to_proplist([{"x-amz-delete-marker", Value} |Rest], Acc) ->
    Tuple = {delete_marker, list_to_existing_atom(Value)},
    response_hdrs_to_proplist(Rest, [Tuple | Acc]);
response_hdrs_to_proplist([{"x-amz-version-id", Value} |Rest], Acc) ->
    Tuple = {version_id, list_to_existing_atom(Value)},
    response_hdrs_to_proplist(Rest, [Tuple | Acc]);
response_hdrs_to_proplist([ {["x-amz-meta-" | Key], Value} |Rest], Acc) ->
    response_hdrs_to_proplist(Rest, [{Key, Value} | Acc]);
response_hdrs_to_proplist([_Ignore |Rest], Acc) ->
    response_hdrs_to_proplist(Rest, Acc).

%% convert a list list of options to a list of headers and 
%% a list of non-header options
opts_to_headers([], HdrsAcc, OptsAcc)  ->
    {HdrsAcc, OptsAcc};
opts_to_headers([{if_modified_since, Value} | Rest], HdrsAcc, OptsAcc) ->
    opts_to_headers(Rest, [{"if-modified-since", Value} | HdrsAcc], OptsAcc);
opts_to_headers([{if_unmodified_since, Value} | Rest], HdrsAcc, OptsAcc) ->
    opts_to_headers(Rest, [{"if-unmodified-since", Value} | HdrsAcc], OptsAcc) ;
opts_to_headers([{if_match, Value} | Rest], HdrsAcc, OptsAcc) ->
    opts_to_headers(Rest, [{"if-match", Value} | HdrsAcc], OptsAcc);
opts_to_headers([{if_none_match, Value} | Rest], HdrsAcc, OptsAcc) ->
    opts_to_headers(Rest, [{"if-none-match", Value} | HdrsAcc], OptsAcc);
opts_to_headers([{range, {Start, Stop}} | Rest], HdrsAcc, OptsAcc) ->
    Val = "bytes="++integer_to_list(Start)++"-"++integer_to_list(Stop),
    opts_to_headers(Rest, [{"range", Val} | HdrsAcc], OptsAcc);

opts_to_headers([NotAHeaderOpt | Rest] , HdrsAcc, OptsAcc) ->
    opts_to_headers(Rest, HdrsAcc, [NotAHeaderOpt | OptsAcc]).

make_metadata_headers(Options) ->
    MetaOpts = get_value(meta, Options, []),
    [{["x-amz-meta-"|string:to_lower(Key)], Value} ||{Key,Value} <- MetaOpts].

-spec get_object_torrent(string(), string()) -> proplists:proplist().
get_object_torrent(BucketName, Key) ->
    get_object_torrent(BucketName, Key, default_config()).

-spec get_object_torrent(string(), string(), config()) -> proplists:proplist().
get_object_torrent(BucketName, Key, Config) ->
    {Headers, Body} = s3_request(Config, get, BucketName, [$/|Key], "torrent", [], [], []),
    [{delete_marker, list_to_existing_atom(get_value("x-amz-delete-marker", Headers, "false"))},
     {version_id, get_value("x-amz-delete-marker", Headers, "false")},
     {torrent, Body}].

-spec list_object_versions(string(), list_object_versions_options()) -> proplists:proplist().
list_object_versions(BucketName, Options) ->
    list_object_versions(BucketName, Options, default_config()).

-spec list_object_versions(string(), list_object_versions_options(), config())-> 
    proplists:proplist().
list_object_versions(BucketName, Options, Config)
  when is_list(BucketName), is_list(Options) ->
    Params = [{"delimiter", get_value(delimiter, Options)},
              {"key-marker", get_value(key_marker, Options)},
              {"max-keys", get_value(max_keys, Options)},
              {"prefix", get_value(prefix, Options)},
              {"version-id-marker", get_value(version_id_marker, Options)}],
    Doc = s3_xml_request(Config,get,BucketName,"/","versions",Params,[],[]),
    Attrs = [{name, "Name", text},
             {prefix, "Prefix", text},
             {key_marker, "KeyMarker", text},
             {next_key_marker, "NextKeyMarker", optional_text},
             {version_id_marker, "VersionIdMarker", text},
             {next_version_id_marker, "NextVersionIdMarker", optional_text},
             {max_keys, "MaxKeys", integer},
             {is_truncated, "Istruncated", boolean},
             {versions, "Version", fun extract_versions/1},
             {delete_markers, "DeleteMarker", fun extract_delete_markers/1}
            ],
    ms3_xml:decode(Attrs, Doc).

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
                 put_object(),
                 put_object_options(),
                 [{string(), string()}]) -> [{'version_id', _}, ...].
put_object(BucketName, Key, Value, Options, HTTPHeaders) ->
    put_object(BucketName, Key, Value, Options, HTTPHeaders, default_config()).

-spec put_object(string(),
                 string(),
                 put_object(),
                 put_object_options(),
                 [{string(), string()}],
                 config()) -> [{'version_id', _}, ...].
put_object(BucketName, Key, Value, Options, HTTPHdrs, Config) ->
    FilteredHdrs = proplists:delete("content-type", HTTPHdrs),
    ACLHdrs = [acl_header(get_value(acl, Options))],
    ContentType = get_value("content-type",HTTPHdrs,"application/octet_stream"),
    MetaHdrs =  make_metadata_headers(Options),
    Hdrs = lists:flatten([ACLHdrs, FilteredHdrs, MetaHdrs]),
    Data = {Value, ContentType},
    Resp = s3_request(Config, put, BucketName, [$/|Key], "", [], Data, Hdrs),
    {RespHdrs, _Body} = Resp,
    [{version_id, get_value("x-amz-version-id", RespHdrs, "null")}].

-spec set_object_acl(string(), string(), proplists:proplist()) -> ok.
set_object_acl(BucketName, Key, ACL) ->
    set_object_acl(BucketName, Key, ACL, default_config()).

-spec set_object_acl(string(), string(), proplists:proplist(), config()) -> ok.
set_object_acl(BucketName, Key, ACL, Config)
  when is_list(BucketName), is_list(Key), is_list(ACL) ->
    Id = get_value(id, get_value(owner, ACL)),
    DisplayName = get_value(display_name, get_value(owner, ACL)),
    ACL1 = get_value(access_control_list, ACL),
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
                            [{'ID', [get_value(id, get_value(owner, Value))]},
                             {'DisplayName', [get_value(display_name, get_value(owner, Value))]}]},
                           {'AccessControlList', encode_grants(get_value(access_control_list, Value))}]},
                {"acl", ACLXML};
            logging ->
                LoggingXML = {'BucketLoggingStatus',
                              [{xmlns, ?XMLNS_S3}],
                              case proplists:get_bool(enabled, Value) of
                                  true ->
                                      [{'LoggingEnabled',
                                        [
                                         {'TargetBucket', [get_value(target_bucket, Value)]},
                                         {'TargetPrefix', [get_value(target_prefix, Value)]},
                                         {'TargetGrants', encode_grants(get_value(target_grants, Value, []))}
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
                Status = case get_value(status, Value) of
                             suspended -> "Suspended";
                             enabled -> "Enabled"
                         end,
                MFADelete = case get_value(mfa_delete, Value, disabled) of
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
    Grantee = get_value(grantee, Grant),
    {'Grant',
     [{'Grantee', [{xmlns, ?XMLNS_S3}],
       [{'ID', [get_value(id, get_value(owner, Grantee))]},
        {'DisplayName', [get_value(display_name, get_value(owner, Grantee))]}]},
      {'Permission', [encode_permission(get_value(permission, Grant))]}]}.

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
    case send_req(URI, get) of
        {ok, {200, _Headers, CredentialsIamRole}} ->
            CredentialsIamRole;
        {ok, {StatusCode, _Headers, _Body}} ->
            erlang:error({iam_error, StatusCode,
                          "Failed to retrieve Amazon IAM Role"})
    end.

%% @TODO Look at refactoring baked_in vs. iam data representation. Avoid
%% unnecessary duplication.
-spec get_credentials(baked_in|iam, headers(), string(), string()) ->
    {headers(), string(), string()}.
get_credentials(baked_in, Headers, AccessKey, SecretKey) ->
    {Headers, AccessKey, SecretKey};
get_credentials(iam, InitialHeaders, _, _) ->
    CredentialsIamRole = binary_to_list(get_credentials_iam_role()),
    URI = ?AMAZON_METADATA_SERVICE ++ "iam/security-credentials/" ++ CredentialsIamRole,
    Resp = send_req(URI, get),
    case Resp of
        {ok, {200, _, JSONBody}} ->
            IAMData = jsx:decode(JSONBody),
            AccessKeyBin = get_value(<<"AccessKeyId">>, IAMData),
            SecretAccessKeyBin = get_value(<<"SecretAccessKey">>, IAMData),
            SecurityToken = get_value(<<"Token">>, IAMData),
            Headers = [{"x-amz-security-token", SecurityToken} | InitialHeaders],
            {Headers, AccessKeyBin, SecretAccessKeyBin};
        {ok, {StatusCode, _Headers, _Body}} ->
            erlang:error({iam_error,
                          StatusCode,
                          "Failed to retrieve Amazon IAM Credentials"})
    end.


%% @TODO: Use the Options lists to reduce the length of this method
%%        signature and try to reduce complexity. If not, consider
%%        using a record or tuple.
-spec s3_request(config(), method(), string(), string(), string(), list(), post_data(), headers()) -> {headers(), binary()}.
s3_request(Conf,Method,Host,Path,Subresource,Params,Data,Hdrs) ->
    s3_request(Conf,Method,Host,Path,Subresource,Params,Data,Hdrs,[]).

-spec s3_request(config(), method(), string(), string(), string(), list(), post_data(), headers(), proplists:proplist()) -> {headers(), binary()}.
s3_request(Conf,Method,Host,Path,Subresource,Params,Data,Hdrs,Opts) ->
    #config{credentials_store=CredentialsStore,
                access_key_id=MaybeAccessKey,
            secret_access_key=MaybeSecretKey} = Conf,
    {Headers, AccessKey, SecretKey} =
        get_credentials(CredentialsStore, Hdrs,
                        MaybeAccessKey, MaybeSecretKey),
    {ContentMD5, ContentType, Body} = hash_post_data(Data),
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
            <<>> -> [];
            _    -> [{"content-md5", ContentMD5}]
        end,
    RequestHeaders1 = case proplists:is_defined("content-type", RequestHeaders0) of
                          true ->
                              RequestHeaders0;
                          false ->
[{"content-type", ContentType} | RequestHeaders0]
                      end,
    RequestURI = lists:flatten([format_s3_uri(Conf, Host),
                                EscapedPath,
                                if_not_empty(Subresource, [$?, Subresource]),
                                if
                                    Params =:= [] -> "";
                                    Subresource =:= "" -> [$?, ms3_http:make_query_string(Params)];
                                    true -> [$&, ms3_http:make_query_string(Params)]
                                end]),
    send_s3_request(RequestURI, Method, RequestHeaders1, Body, Opts).

-spec send_s3_request(string(),atom(),headers(),iodata(),httpc_opts()) ->
    {headers(), binary()}.
send_s3_request(URI, Method, Headers, Body, Opts) ->
    Response = case Method of
        get ->
            send_req(URI, get, Headers, Opts);
        delete ->
            send_req(URI, delete, Headers, Opts);
        head ->
            %% ibrowse is unable to handle HEAD request responses that are sent
            %% with chunked transfer-encoding (why servers do this is not
            %% clear). While we await a fix in ibrowse, forcing the HEAD request
            %% to use HTTP 1.0 works around the problem.
            %%
            %% @TODO: Verify this against live Amazon S3 using dlhttpc
            send_req(URI, head, Headers, Opts);
        _ ->
            %% @TODO: I think this is 'put' only. Let's make it explicit
            send_req(URI, put, Headers, Body, Opts)
    end,
    parse_s3_response(Response).

% @TODO Clean up this ugly method signature.:
-spec hash_post_data({PostData    :: iolist()
                                   | {stream_from, filename()}
                                   | {stream_from, {filename(),
                                                    chunk_size_bytes()}},
                      ContentType :: string()
                     }) ->
    {Hash        :: string(), 
     ContentType :: string(),
     Body        :: iolist()
                  | {stream_from, {filename(), chunk_size_bytes()}}
                  | {stream_from, filename()}
    }.
hash_post_data({{stream_from,{Filename, ChunkSize}} = POSTData,ContentType}) ->
    {base64_hash_file(Filename, ChunkSize), ContentType, POSTData};
hash_post_data({{stream_from, Filename} = POSTData, ContentType}) ->
    {base64_hash_file(Filename, ?DEFAULT_CHUNK_SIZE), ContentType, POSTData};
hash_post_data({POSTData, ContentType}) ->
    {base64:encode_to_string(crypto:hash(md5,POSTData)), ContentType, POSTData};
hash_post_data(POSTData) ->
    %% On a put/post even with an empty body we need some content-type
    {"", "text/xml", POSTData}.
-spec base64_hash_file(Filename  :: filename(),
                       ChunkSize :: chunk_size_bytes())->
    {ok, string()} | {error, Reason::any()}.
base64_hash_file(Filename, ChunkSize) ->
    base64_hash_file(Filename, ChunkSize, md5).

-spec base64_hash_file(Filename  :: filename(),
                       ChunkSize :: chunk_size_bytes(),
                       Algorithm :: crypto:hash_algorithms()) ->
    base64:ascii_binary() | {error, Reason::any()}.
base64_hash_file(Filename, ChunkSize, Algorithm) ->
    case hash_file(Filename, ChunkSize, Algorithm) of
        {ok, Hash}      -> base64:encode_to_string(Hash);
        {error, Reason} -> {error, Reason}
    end.

-spec hash_file(Filename  :: filename(),
                ChunkSize :: chunk_size_bytes(),
                Algorithm :: crypto:hash_algorithms()) ->
    {ok, hash()} | {error, Reason::any()}.
hash_file(Filename, ChunkSize, Algorithm) ->
    HashContext = crypto:hash_init(Algorithm),
    case file:open(Filename, [read, raw, binary]) of 
        {ok, File} ->
            Data = file:read(File, ChunkSize),
            hash_file(File, ChunkSize, HashContext, Data);
        {error, Reason} ->
            {error, Reason}
    end.
    
-spec hash_file(File        :: file:file(),
                ChunkSize   :: chunk_size_bytes(),
                HashContext :: any(),
                ReadResult  :: {ok, Data::binary()} | eof | {error, any()}) ->
    {ok, hash()} | {error, Reason::any()}.
hash_file(File, _ChunkSize, HashContext, eof) ->
    case file:close(File) of
        ok ->
            {ok, crypto:hash_final(HashContext)};
        {error, Reason} ->
            {error, Reason}
    end;
hash_file(File, ChunkSize, HashContext, {ok, Data}) ->
    NewContext = crypto:hash_update(HashContext, Data),
    NewData = file:read(File, ChunkSize),
    hash_file(File, ChunkSize, NewContext, NewData);
hash_file(_File, _ChunkSize, _HashContext, {error, Reason}) ->
    {error, Reason}.

-spec parse_s3_response(http_response()) -> {headers(), binary()}.
parse_s3_response({error, Error}) ->
    erlang:error({aws_error, {socket_error, Error}});
parse_s3_response({ok, {StatusCode, Headers, Body}}) ->
    Headers1 = canonicalize_headers(Headers),
    case StatusCode >= 200 andalso StatusCode =< 299 of
        true ->
            {Headers1, Body};
        false ->
            erlang:error({aws_error, {http_error, StatusCode, {Headers,Body}}})
    end.

%% Shorthand for proplists:get_value/2
get_value(Key, List) ->
    get_value(Key, List, undefined).
    
%% Shorthand for proplists:get_value/3
get_value(Key, List, Default) ->
    proplists:get_value(Key, List, Default).

-spec send_req(string(), method() | string()) -> http_response().
send_req(URI, Method) ->
    send_req(URI, Method, [], [], []).

-spec send_req(string(), method(), headers(), httpc_opts()) ->
    http_response().
send_req(URI, Method, Headers, Opts) ->
    send_req(URI, Method, Headers, [], Opts).

send_req(URI, Method, Headers, Body, Opts) ->
    httpc_impl:send_req(URI, Method, Headers, Body, Opts).

%% TODO: get rid of subresource throughout the codebase. Instead,
%%       if a version_id is present, simply append:
%%       "?version_id=" ++ VersionID to Resource
%%
-spec make_authorization(AccessKeyId::binary(),
                         SecretKey::binary(),
                         Method::atom(),
                         ContentMD5::binary(),
                         ContentType::string(),
                         Date::string(),
                         AmzHeaders::headers(),
                         Host::string(),
                         Resource::string(),
                         Subresource::string()) ->
    {StringToSign::string(), Signature::string()}.
make_authorization(AccessKeyId, SecretKey, Method, ContentMD5, ContentType, Date, AmzHeaders, Host, Resource, Subresource) ->
    CanonizedAmzHeaders =
        [[Name, $:, Value, $\n] || {Name, Value} <- lists:sort(AmzHeaders)],
    %% It's called String to sign in Amazon documentation, however in
    %% our implementation, it is an iolist()
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
