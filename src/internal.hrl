%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
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

-record(config, {
          s3_url = "http://s3.amazonaws.com"  :: string(),
          credentials_store                   :: iam | baked_in,
          access_key_id                       :: binary(),
          secret_access_key                   :: binary(),
          bucket_access_type = virtual_hosted :: mini_s3:bucket_access_type()
}).

% metadata service is only used from within an instance.
-define(AMAZON_METADATA_SERVICE,"http://169.254.169.254/latest/meta-data/").

-define(DEFAULT_CHUNK_SIZE, 64*1024). % 64kb chunks for streaming
-define(DEFAULT_HTTP_TIMEOUT, 5000). % 5 seconds
-define(XMLNS_S3, "http://s3.amazonaws.com/doc/2006-03-01/").

