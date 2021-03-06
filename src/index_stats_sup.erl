%% @author Couchbase, Inc <info@couchbase.com>
%% @copyright 2015 Couchbase, Inc.
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
-module(index_stats_sup).

-include("ns_common.hrl").

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Childs =
        [{index_stats_childs_sup, {supervisor, start_link, [{local, index_stats_childs_sup}, ?MODULE, child]},
          permanent, infinity, supervisor, []},
         {index_stats_worker, {erlang, apply, [fun start_link_worker/0, []]},
          permanent, 1000, worker, []},
         {index_status_keeper, {index_status_keeper, start_link, []},
          permanent, 1000, worker, []},
         {index_stats_collector, {index_stats_collector, start_link, []},
          permanent, 1000, worker, []}],
    {ok, {{one_for_all,
           misc:get_env_default(max_r, 3),
           misc:get_env_default(max_t, 10)},
          Childs}};
init(child) ->
    {ok, {{one_for_one,
           misc:get_env_default(max_r, 3),
           misc:get_env_default(max_t, 10)},
          []}}.

is_notable_event({buckets, _}) ->
    true;
is_notable_event(_) ->
    false.

handle_cfg_event(Event) ->
    case is_notable_event(Event) of
        false ->
            ok;
        true ->
            work_queue:submit_work(index_stats_worker, fun refresh_childs/0)
    end.

compute_wanted_childs(Config) ->
    case ns_cluster_membership:should_run_service(Config, index, node()) of
        false -> [];
        true ->
            BucketCfgs = ns_bucket:get_buckets(Config),
            BucketNames = [Name || {Name, BConfig} <- BucketCfgs,
                                   lists:keyfind(type, 1, BConfig) =:= {type, membase}],
            lists:sort([{Mod, Name}
                        || Name <- BucketNames,
                           Mod <- [stats_archiver, stats_reader]])
    end.

refresh_childs() ->
    RunningChilds0 = [Id || {Id, _Child, _Type, _Modules} <- supervisor:which_children(index_stats_childs_sup)],
    RunningChilds = lists:sort(RunningChilds0),
    WantedChilds0 = compute_wanted_childs(ns_config:get()),
    WantedChilds = ordsets:union(WantedChilds0, ["@index"]),
    ToStart = ordsets:subtract(WantedChilds, RunningChilds),
    ToStop = ordsets:subtract(RunningChilds, WantedChilds),
    [start_new_child(Mod, Name) || {Mod, Name} <- ToStart],
    [stop_child({Mod, Name}) || {Mod, Name} <- ToStop],
    ok.

start_new_child(Mod, Name) when Mod =:= stats_archiver; Mod =:= stats_reader ->
    {ok, _Pid} = supervisor:start_child(
                   index_stats_childs_sup,
                   {{Mod, Name},
                    {Mod, start_link, ["@index-" ++ Name]},
                    permanent, 1000, worker, []}).

stop_child(Id) ->
    ok = supervisor:terminate_child(index_stats_childs_sup, Id),
    ok = supervisor:delete_child(index_stats_childs_sup, Id).

start_link_worker() ->
    RV = {ok, _} = work_queue:start_link(
                     index_stats_worker,
                     fun () ->
                             ns_pubsub:subscribe_link(ns_config_events, fun handle_cfg_event/1)
                     end),
    work_queue:submit_work(index_stats_worker, fun refresh_childs/0),
    RV.
