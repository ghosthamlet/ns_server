%% @author Northscale <info@northscale.com>
%% @copyright 2010 NorthScale, Inc.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%      http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% @doc Macros used all over the place.
%%

-type histogram() :: [{atom(), non_neg_integer()}].
-type map() :: [[atom(), ...], ...].
-type moves() :: [{non_neg_integer(), atom(), atom()}].
-type bucket_name() :: nonempty_string().
-type bucket_type() :: memcached | membase.


-define(LOG(Fun, Format, Args),
        error_logger:Fun("~s:~s:~B: " ++ Format ++ "~n",
                         [node(), ?MODULE, ?LINE] ++ Args)).

-define(log_info(Format, Args), ?LOG(info_msg, Format, Args)).
-define(log_warning(Format, Args), ?LOG(warning_msg, Format, Args)).
-define(log_error(Format, Args), ?LOG(error_msg, Format, Args)).
