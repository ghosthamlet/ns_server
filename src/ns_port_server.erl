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
-module(ns_port_server).

-define(ABNORMAL, 0).

-behavior(gen_server).

-include("ns_common.hrl").

%% API
-export([start_link/4]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

-define(NUM_MESSAGES, 3). % Number of the most recent messages to log on crash

-define(UNEXPECTED, 1).

-include_lib("eunit/include/eunit.hrl").

%% Server state
-record(state, {port, name, messages}).


%% API

start_link(Name, Cmd, Args, Opts) ->
    gen_server:start_link(?MODULE,
                          {Name, Cmd, Args, Opts}, []).

init({Name, _Cmd, _Args, _Opts} = Params) ->
    process_flag(trap_exit, true), % Make sure terminate gets called
    Port = open_port(Params),
    {ok, #state{port = Port, name = Name,
                messages = ringbuffer:new(?NUM_MESSAGES)}}.

handle_info({_Port, {data, {_, Msg}}}, State) ->
    {Msgs, Dropped} = fetch_messages(99, 1000),
    L = [Msg|Msgs],
    %% Store the last messages in case of a crash
    Messages = lists:foldl(fun ringbuffer:add/2, State#state.messages, L),
    error_logger:info_msg(format_lines(State#state.name, L)),
    if Dropped > 0 ->
            ?log_warning("Dropped ~p log lines from ~p",
                         [Dropped, State#state.name]);
       true ->
            ok
    end,
    {noreply, State#state{messages=Messages}};
handle_info({_Port, {exit_status, 0}}, State) ->
    {stop, normal, State};
handle_info({_Port, {exit_status, Status}}, State) ->
    ns_log:log(?MODULE, ?ABNORMAL,
               "Port server ~p on node ~p exited with status ~p. Restarting. "
               "Messages: ~s",
               [State#state.name, node(), Status,
                string:join(ringbuffer:to_list(State#state.messages), "\n")]),
    {stop, {abnormal, Status}, State}.

handle_call(unhandled, unhandled, unhandled) ->
    unhandled.

handle_cast(unhandled, unhandled) ->
    unhandled.

terminate(_Reason, #state{port=Port}) ->
    try port_close(Port) of
        true ->
            ok
    catch error:badarg ->
            ok
    end.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% Internal functions

%% @doc Fetch up to Max messages from the queue, discarding any more
%% received up to Timeout. The goal is to remove messages from the
%% queue as fast as possible if the port is spamming, avoiding
%% spamming the log server.
fetch_messages(Max, Timeout) ->
    fetch_messages(Max, Timeout, now(), [], 0).

fetch_messages(Max, Timeout, Now, L, Dropped) ->
    receive
        {_Port, {data, {_, Msg}}} ->
            {L1, D1} = if length(L) < Max ->
                               {[Msg|L], Dropped};
                          true ->
                               %% Drop the message
                               {L, Dropped + 1}
                 end,
            fetch_messages(Max, Timeout, Now, L1, D1)
    after erlang:max(Timeout - timer:now_diff(now(), Now), 0) ->
            {lists:reverse(L), Dropped}
    end.

format_lines(Name, Lines) ->
    Prefix = io_lib:format("~p~p: ", [Name, self()]),
    [[Prefix, Line, $\n] || Line <- Lines].

open_port({_Name, Cmd, Args, OptsIn}) ->
    %% Incoming options override existing ones (specified in proplists docs)
    Opts0 = OptsIn ++ [{args, Args}, exit_status, {line, 8192},
                       stderr_to_stdout],
    WriteDataArg = proplists:get_value(write_data, Opts0),
    Opts = lists:keydelete(write_data, 1, Opts0),
    Port = open_port({spawn_executable, Cmd}, Opts),
    case WriteDataArg of
        undefined ->
            ok;
        Data ->
            Port ! {self(), {command, Data}}
    end,
    Port.
