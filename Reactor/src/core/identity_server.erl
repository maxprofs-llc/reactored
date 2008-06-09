%%  Copyright (C) 2008 Alan Wood
%%  This file is part of Reactored

%%     Reactored is free software: you can redistribute it and/or modify
%%     it under the terms of the GNU General Public License as published by
%%     the Free Software Foundation, either version 2 of the License, or
%%     (at your option) any later version.

%%     Reactored is distributed in the hope that it will be useful,
%%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%     GNU General Public License for more details.

%%     You should have received a copy of the GNU General Public License
%%     along with Reactored.  If not, see <http://www.gnu.org/licenses/>.

%%     Further information about Reactored and it's ideas can be found at
%%     http://www.Reactored.org/

%%%-------------------------------------------------------------------
%%% File    : identity_server.erl
%%% Author  : Alan Wood <awood@alan-woods-macbook.local>
%%% Description : 
%%%
%%% Created :  1 Jun 2008 by Alan Wood <awood@alan-woods-macbook.local>
%%%-------------------------------------------------------------------
-module(identity_server).
-include("schema.hrl").
-include("system.hrl").
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([start/0,stop/0]).
-export([authenticate/2,create/3,delete/1,filter/4,authorise/4,controls/4]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-record(state, {}).

%%====================================================================
%% API
%%====================================================================
authenticate(Id,Pswd) ->
    gen_server:call(?MODULE,{authenticate,Id,Pswd}).

create(Domain,Item,Attributes) ->
    gen_server:call(?MODULE,{create,Domain,Item,Attributes}).

delete(Item) ->
    gen_server:call(?MODULE,{delete,Item}).


filter(Meta,Actor,Domain,Q) ->
    gen_server:call(?MODULE,{filter,Meta,Actor,Domain,Q}).

authorise(Credentials,Service,Command,Request) ->
    gen_server:call(?MODULE,{authorise,Credentials,Service,Command,Request}).

%% ACL controls
controls(Credentials,Service,Command,Request) ->
    gen_server:call(?MODULE,{controls,Credentials,Service,Command,Request}).

%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start() -> start_link().
stop() -> gen_server:call(?MODULE,stop).
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call({authenticate,Id,Pswd}, _From, State) ->
    Reply = case apply(identity_adaptor(),authenticate,[Id,Pswd]) of
	ok -> 
		    ok;
	Bad -> 
	    % Identity module error/ not loaded?
	    {error,error({"Identity modul return error, could, be a missing module",Bad})}
    end,
    {reply, Reply, State};

handle_call({create,Domain,Item,Attributes}, _From, State) ->
    Reply = case apply(identity_adaptor(),create,[qualified(Domain,Item),Attributes]) of
	ok-> 
	    ok;
	Bad -> 
	    % Identity module error/ not loaded?
	    {error,error({"Identity modul return error, could, be a missing module",Bad})}
    end,
    {reply, Reply, State};
handle_call({delete,Item}, _From, State) ->
    Reply = case apply(identity_adaptor(),delete,[Item]) of
		{ok,Id} -> % Delete privileges associated with this participant
		    index_server:delete_controls(Item),
		    {ok,Id};
		Bad -> 
		% Identity module error/ not loaded?
		    {error,error({"Identity modul return error, could, be a missing module",Bad})}
    end,
    {reply, Reply, State};
handle_call({filter,tagged,{uri,Author},_Domain,{Tags,Author}}, _From, State) ->
    Reply = summarise(index_server:tagged(Tags,get_index_id(Author))),
    {reply, Reply, State};
handle_call({filter,tagged,Actor,_Domain,Tags}, _From, State) ->
    Reply = screen(Actor,index_server:tagged(Tags)),
    {reply, Reply, State};
handle_call({filter,search,Actor,_Domain,Q}, _From, State) ->
    Reply = screen(Actor,index_server:search(Q)),
    {reply, Reply, State};
%% Todo Need to double check the restrictions on this action
handle_call({filter,profile,_Actor,_Domain,Profile}, _From, State) ->
    Reply = summarise(index_server:profile(Profile)),
    {reply, Reply, State};
handle_call({filter,q,Actor,Domain,Attributes}, _From, State) ->
    Reply = screen(Actor,Domain, Attributes),
    {reply, Reply, State};
%% this needs to point to index_server
handle_call({filter,graph,Actor,Domain,{Uri,Attributes}}, _From, State) ->
    Reply = screen(Actor,Domain, Uri, Attributes),
    {reply, Reply, State};

handle_call({authorise,Credentials,Service,Command,Request}, _From, State) ->
    Reply = case check_access(Credentials,Service,Command,Request) of
	{ok,Uri}-> 
		    {ok,Uri};
	{error,Iuri,Why} -> 
	    % Authosrisation failure
	    {error,error({"could not authorise. " ++ Iuri ++ "," ++ Why})}
    end,
    {reply, Reply, State};

handle_call({controls,Credentials,_Service,add_acl,Request}, _From, State) ->
    Reply = add(Credentials,Request),
    {reply, Reply, State};
handle_call({controls,Credentials,_Service,remove_acl,Request}, _From, State) ->
    Reply = remove(Credentials,Request),
    {reply, Reply, State};


handle_call(stop, _From, State) ->
    {stop,normal,stopped, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

%% This stuff needs to be much clearer visually (seperate files)
check_access({annonymous},_Service,retrieve,_Request) -> % annonomous can only retrieve
    {ok,"reactored.com/Users/annonymous"};
check_access({annonymous},_Service,Command,_Request) ->
    Reason = "Credentials not suitable, example authentication failure",
    {error,"/Users/annonymous",atom_to_list(Command) ++ " failed dues to :"  ++ Reason};
%% A participant can do all of this things with their own profile
check_access({uri,Iuri},_Service,retrieve,{Iuri,_Attributes}) -> {ok,Iuri};
check_access({uri,Iuri},_Service,update,{Iuri,_Attributes}) -> {ok,Iuri};
check_access({uri,Iuri},_Service,create,{Iuri,_Attributes}) -> {ok,Iuri};
check_access({uri,Iuri},_Service,q,{Iuri,_Attributes}) -> {ok,Iuri};

check_access({uri,Iuri},_Service,Command,{Uri,Attributes}) -> 
    check_privileges(Iuri,Uri,Command,get_privileges(Iuri,{Uri,Attributes}));
check_access({token,Token},_Service,Command,{Uri,Attributes}) -> 
    Iuri = get_uri_from_token(Token),
    check_privileges(Iuri,Uri,Command,get_privileges(Iuri,{Uri,Attributes}));
check_access(_Credential,Service,Command,Request) ->
    {error,error({"Badly formed Credentials for command ",atom_to_list(Command) ++ ",Credentials not recognised ",Service,Command,Request})}.

get_privileges(Iuri,{Uri,_Attributes}) ->
    index_server:controls(Iuri,Uri).

check_privileges(Iuri,_Uri,Command,[Command|_Controls]) ->
    {ok,Iuri};
check_privileges(Iuri,Uri,Command,[_Control|Controls]) ->
    check_privileges(Iuri,Uri,Command,Controls);
check_privileges(Iuri,Uri,Command,[]) ->
    {error,Iuri,"No control allowing " ++ Iuri ++ " to " ++ atom_to_list(Command)  ++ " " ++ Uri}.

screen(Actor,Lids) ->
    summarise(index_server:controls(Actor,retrieve,Lids)).

screen(Actor,Domain, Attributes) ->
    Results = attribute_server:q(Domain,Attributes),
    Uris = index_server:controls(Actor,retrieve,[It#item.created || It <- Results]),
    lists:filter(fun(I) -> lists:member(I#item.item,Uris) end,Results).

screen(Actor,Domain, Uri, Attributes) ->
    Results = case attribute_server:graph(Domain, Uri, Attributes) of
		  {atomic,{_Item,Items}} -> 
		      Items;
		  _ -> 
		      error({"No results for graph query ",Domain, Uri, Attributes}),
		      []
	      end,
    Uris = index_server:controls(Actor,retrieve,[It#item.created || It <- Results]),
    lists:filter(fun(I) -> lists:member(I#item.item,Uris) end,Results).

add({uri,Iuri},{Uri,Attributes}) ->
    index_server:add_controls(Iuri,Uri,get_acl(Attributes)).
remove({uri,Iuri},{Uri,Attributes}) ->
    index_server:remove_controls(Iuri,Uri,get_acl(Attributes)).

identity_adaptor() ->
    ?DEFAULTIDADAPTOR.

summarise(Locations) -> 
    summarise(Locations,[]).
%TODO this needs to adapt to different incoming types, control records or {lid,tag} depending on if profile,tagged or search query. Maybe we dont need index anymore, just useattribute_server:retrieve_by_created(item.created) ?
summarise([{Lid,Tag}|Locations],Summary) -> % Tagged Auth
    [Item] = attribute_server:retrieve(Lid),
    summarise(Locations,[{Tag,Item}|Summary]);
summarise([{_id,_iid,Lid,_types}|Locations],Summary) -> % Profile returns control records
    [Item] = attribute_server:retrieve(Lid),
    summarise(Locations,[{Item}|Summary]);
summarise([],Summary) ->
    Summary.
%% redundant now    
%% summarise([Location|Locations],Summary) ->
%%     L = attribute_server:retrieve(Location, basic)
%%     summarise(Locations,[{L#item.title,limit(L#item.descrption),L#item.uri} | Summary])


%% limit(Text) ->
%%     sublist(markup_stripper:parse(Text), ?SUMCHARS).

%% domain(Qitem) ->
%%     attribute:domain_from_qitem(Qitem).

%% qualified(Domain,Item) ->
%%     attribute:item_id(Domain,Item).

get_acl(Attributes) ->
    case proplist:lookup("acl",Attributes) of
	none -> [];
	{_,undefined} -> []; 
	{_,Acl} -> lists:map(fun list_to_atom/1,string:tokens(Acl,","))
    end.

%% Todo implement tokens
get_uri_from_token(Token) ->
    error("Tokens not yet implemented"),
    [].

get_index_id(Uri) ->
    index_server:get_index_id(Uri).

qualified(Domain,Item) ->
    attribute:item_id(Domain,Item).

error(Error) ->
    error_logger:error_msg("Identity server - Says Whoops ~p~n",[Error]),
    Error.
