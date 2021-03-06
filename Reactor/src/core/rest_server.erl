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
%%% File    : rest_server.erl
%%% Author  : Alan Wood <awood@alan-woods-macbook.local>
%%% Description : 
%%%
%%% Created : 19 Jun 2008 by Alan Wood <awood@alan-woods-macbook.local>
%%%-------------------------------------------------------------------
-module(rest_server).
-author('awood@alan-woods-macbook.local').
-include("schema.hrl").
-include("system.hrl").
-include_lib("stdlib/include/qlc.hrl").
-export([indexes/0]).
-export([start/1, stop/0, react_to/2]).


indexes() ->
    F = fun() -> 
		qlc:e(qlc:q([X || X <- mnesia:table(usession)]))
	end,
    mnesia:transaction(F).

%% External API

start(Options) ->
    {DocRoot, Options1} = rest_helper:get_option(docroot, Options),
    Loop = fun (Req) ->
                   ?MODULE:react_to(Req, DocRoot)
           end,
    mochiweb_http:start([{name, ?MODULE}, {loop, Loop} | Options1]).

stop() ->
    mochiweb_http:stop(?MODULE).

%% Reactor main http dispatch
react_to(Request, DocRoot) ->
    react_to(Request:get(method),Request:get(path),Request, DocRoot).

%% Homes
%% react_to(Method,"/",Request,DocRoot) ->
%%     react_to(Method,"/static/index.html",Request, DocRoot);
%% react_to(Method,"/index.html",Request,DocRoot) ->
%%     react_to(Method,"/static/index.html",Request, DocRoot);
%% react_to(Method,"/index.htm",Request,DocRoot) ->
%%     react_to(Method,"/static/index.html",Request, DocRoot);
%% react_to(Method,"/home.html",Request,DocRoot) ->
%%     react_to(Method,"/static/index.html",Request, DocRoot);
%% react_to(Method,"/home.htm",Request,DocRoot) ->
%%     react_to(Method,"/static/index.html",Request, DocRoot);
%% react_to(Method,"/_/error",Request,DocRoot) ->
%%     redirect(retrieve,"/static/error.html",Request,[]);

%% Special cases for actor based interactions
% Tag resource (or external url) using 'GET'

% Special functions - short cut to actor's identity page
react_to(Method,"/home" ++ Resource,Request,_DocRoot) ->
    react_to(Method,"/~" ++ Resource,Request,_DocRoot);
react_to(_Method,"/~",Request,_DocRoot) ->
    io:format("Home ~s~n",["Where the heart is"]),
    case rest_helper:credentials(Request) of
	{uri,Actor} ->
	    Url = rest_helper:item_to_url(Actor),
	    io:format("Redirecting to ~s~n",[Url]),
	    rest_helper:redirect(retrieve,"http://" ++ Url,Request,[]);
	_ -> 
	    rest_helper:redirect(retrieve,rest_helper:domain(Request) ++ "_login",Request,[])
    end;

react_to(Method,"/~" ++ Resource,Request,_DocRoot) ->
    case rest_helper:attributes_and_actor(Request,Method) of
	{_,{annonymous}} ->
	    rest_helper:forbidden(Resource,Request,"You have to be logged in to access your resources");
	{Attributes,Credentials} ->
	    rest_reactors:respond_to(actor,adaptor(lists:reverse(Resource),rest_helper:accepts(Request)),Method,"~"++ Resource,Credentials,Attributes,Request)
    end;

%% Reactor REST dispatcher
react_to(Method,?CONTEXT,Request, DocRoot) ->
    % ToDo Maybe this should be allowed top level root items? everything?
    Request:respond({501, [], []});
react_to(Method,?CONTEXT ++ Resource,Request,_DocRoot) ->
    react_to(Method,Resource,Request);

%% Reactor public Resource dispatcher
react_to(Method,?PUBLIC,Request, DocRoot) ->
    % ToDo Should pick up home instead  - index.html/htm etc..
    Request:respond({501, [], []});
react_to(Method,?PUBLIC ++ Path,Req, DocRoot) ->
    case Req:get(method) of
	Method when Method =:= 'GET'; Method =:= 'HEAD' ->
	    case Path of
		_ ->
		    Req:serve_file(Path, DocRoot ++ ?PUBLIC)
	    end;
	_ ->
	    Req:respond({501, [], []})
    end;
%% Logging out
react_to('GET',?LOGOUT,Request,DocRoot) ->
    rest_helper:remove_session(Request),
    Request:respond({200, [{"Content-Type", "text/html"} | []], rest_helper:html("<h3>You are now logged out</h3><p><a href=\"/_login\">Login</a></p>")});
%% Logging into REST interface
%% Todo implement plain http login as an alternative to form based login
react_to('GET',?LOGIN,Request,DocRoot) ->
    io:format("Cookie ~p~n",[Request:get_cookie_value(?COOKIE)]),
    rest_helper:show_login_form(Request); % TODO we might just forward to /static/login.html instead, same below on login errors
react_to('POST',?LOGIN,Request,DocRoot) ->
    io:format("~n Authenticating ~n"),
    Attributes = rest_helper:attributes('POST',Request),
    %% Todo need to handle cases where login params are no provided
    Id = proplists:get_value("identity", Attributes),
    Pswd = proplists:get_value("password", Attributes),
    case identity_server:authenticate(Id,Pswd) of
	{ok,Actor} -> 
	    io:format("Authenticated ~s~n",[Actor]), 
	    Header = rest_helper:save_session(Request,Actor),
	    %io:format("Headers ~p~n",[Header]),
	    %redirect(create,Actor,Request,[Header]);
	    case proplists:get_value("redirect", Attributes) of
		   undefined ->
		    Request:respond({200, [{"Content-Type", "text/html"} | [Header]], rest_helper:html("<h3>Logged in</h3>")});
		Destination ->
		    Request:respond({303, [{"Location",Destination}| [Header]], rest_helper:a(Destination)});
		_ ->
		    Request:respond({200, [{"Content-Type", "text/html"} | [Header]], rest_helper:html("<h3>Logged in, but could not redirected</h3>")})
	    end;
	{error,Error} ->
	    io:format("Not authenticated ~s~n",[Error]),
	    rest_helper:show_login_form(Request,Error)
    end; 

%% Reactor Resource dispatcher
react_to(Method,?RESOURCES,Request, DocRoot) ->
    Request:respond({501, [], []});

react_to('POST',?RESOURCES ++ Path,Request, DocRoot) ->
    Credentials = rest_helper:credentials(Request),
    case lists:last(Path) of
	$/ ->
	    R = case string:tokens(Path, "/") of
			   [_] ->
			       Path;
			   R1 -> 
			       string:join(R1,"/")
		       end,
	    case actor_server:lookup(rest_helper:qres(R,Request)) of
		[] ->
		    rest_helper:error(html_adaptor,create,Path,Request,"Cannot create Upload resource as child of unknown resource/domain " ++ R);
		Qitem ->
		    case identity_server:authorise(Credentials,rest_server,create,{Qitem,[]}) of 
			{ok,_Actor} ->
			    case upload:store(Path,Request) of
				{ok,File,Title,Link,Type,Filename} ->
				    io:format("Uploaded ~s~n",[File]),

				    [Domain,Res] = string:tokens(Qitem,?DOMAINSEPERATOR),
				    R2 = case Res of 
					     "/" ->
						 Res;
					     _ ->
						 Res ++ "/"
					 end,
				    Item = R2 ++ "upload_" ++ attribute:today(),
				    Title1 = case Title of
						 undefined -> 
						     Filename;
						 "?" ->
						     Filename;
						 "" ->
						     Filename;
						 _ ->
						     Title
					     end,    
				    Attributes = [{"title",Title1},{"description",rest_helper:link(Title1,"/" ++ Link,"_blank") ++ " uploaded resource "},{"type",rest_helper:safeUri(Type)}],
				    case actor_server:create(Credentials,?MODULE,Domain,Item,Attributes) of
					{ok,_Xref} ->
					    Request:respond({200,[{"Content-Type","text/html"}],rest_helper:html("<h1>File uploaded</h1>")});
					{autherror,Why} ->
					    error({"Authentication Error adding upload",Why,Title}),
					    rest_helper:forbidden(html_adaptor,'POST',?RESOURCES ++ Path,Request,"<h1>Sorry but you do not have access privelages to upload here</h1>");
					{error,Error} ->
					    error({"Error adding upload message",Error,Title}),
					    rest_helper:error(html_adaptor,'POST',?RESOURCES ++ Path,Request,"<h1>Sorry an error occured uploading your file</h1>")
				    end;    
			    {error,Error,Resp} ->
				error({"Uploading error",Error,Resp}),
				rest_helper:error(html_adaptor,'POST',?RESOURCES ++ Path,Request,"<h1>Sorry an error occured uploading your file</h1>");
			    _ -> 
				error({"Upload failure",Path}),
				rest_helper:error(html_adaptor,'POST',?RESOURCES ++ Path,Request,"<h1>Sorry an error occured uploading your file</h1>")
			    end;
			{error,Actor,Why} ->
			    error(Why),
			    rest_helper:forbidden(?RESOURCES ++ Path,Request,"You do not have the access privelages to upload to this resource")
		    end
		end;
	_ ->
	    error({"Upload failure cannot upload to Resource ",Path}),
	    rest_helper:error(html_adaptor,'POST',?RESOURCES ++ Path,Request,"<h1>Sorry an error occured uploading your file</h1>")
    end;


react_to(Method,?RESOURCES ++ Path,Request, DocRoot) ->
    [Dom|Resource] = string:tokens(Path,"/"),
    Domain = rest_helper:qres(Dom,Request),
    {_Attributes,Credentials} = rest_helper:attributes_and_actor(Request,Method),
    case Credentials of
	{annonymous} ->
	    rest_helper:forbidden(Resource,Request,"You have to be logged in to access domain resources");
	{uri,Actor} -> 
	    case Request:get(method) of
		Method when Method =:= 'GET'; Method =:= 'HEAD' ->
		    case Path of
			_ ->
			    case identity_server:authorise(Credentials,rest_server,retrieve,{Domain ++ ?DOMAINSEPERATOR ++ "/",[]}) of 
				{ok,_Actor} ->
				    io:format("Retrieving resource ~s~n",[Path]),
				    Request:serve_file(Path, DocRoot ++ ?RESOURCES);
				{error,Actor,Why} ->
				    error(Why),
				    rest_helper:forbidden(Resource,Request,"You do not have the access privelages to retrieve this resource")
			    end
			    
		    end;
		_ ->
		    Request:respond({501, [], []})
	    end
    end;

% Domain Interceptors (proxies etc..)
react_to(_Method,"/",Request, _DocRoot) ->
    Request:respond({404, [], []});
react_to(Method,"/" ++ Path,Request,_DocRoot) ->
    [Dom|Resource] = string:tokens(Path,"/"),
    Domain = rest_helper:qres(Dom,Request),
    {_Attributes,Credentials} = rest_helper:attributes_and_actor(Request,Method),
    case Credentials of
	{annonymous} ->
	    rest_helper:forbidden(Resource,Request,"You have to be logged in to access domains");
	{uri,Actor} -> 
	    % ToDo optimise by using a lookup call rather than this heavy query
	    case domain:retrieve(Domain) of
		{atomic,[]} ->
		    rest_helper:error(html_adaptor,Method,"/_" ++ Path,Request,"No domain for interceptor");
		_ ->
		    io:format("about to call intercept Domain ~p~n",[Domain]),
		    case domain_server:intercept(Domain,Method,Resource,Request,Actor) of
			{error,forbidden} ->
			    rest_helper:forbidden(Resource,Request,"You have to be logged in to create or update resources");
			{error,Reason} ->
			    error(Reason),
			    rest_helper:error(html_adaptor,Method,"/_" ++ Path,Request,"Sorry an error occured with your request");
			{ok,{Code, Result}} ->	    
			    Request:respond({Code, [], Result});
			{ok,{Status,Headers,Result}} ->
			    {_Vers, Code, _Reason} = Status,	    
			    Request:respond({Code, Headers, Result});
			{ok,Result} ->
			    Request:respond({200,[{"Content-Type","text/html"}],Result});
			_ ->
			    rest_helper:error(html_adaptor,Method,"/_" ++ Path,Request,"Could not handle request")
		    end
	    end
    end.

%% Basic REST Operations
react_to('HEAD',Url,Request) -> 
    %% Todo optimise HEAD calls
    case rest_helper:split(Url) of
	{Resource,Ext} ->
	    {Attributes,Credentials} = rest_helper:attributes_and_actor(Request,'HEAD'),
	    rest_reactors:respond_to(adaptor(Ext,rest_helper:accepts(Request)),retrieve,Resource,Credentials,Attributes,Request);
	_ ->
	    rest_helper:error(html_adaptor,'HEAD',Url,Request,"Illegal resource request")
    end;
react_to('GET',Url,Request) -> 
    case rest_helper:split(Url) of
	{Resource,Ext} ->
	    {Attributes,Credentials} = rest_helper:attributes_and_actor(Request,'GET'),
	    rest_reactors:respond_to(adaptor(Ext,rest_helper:accepts(Request)),retrieve,Resource,Credentials,Attributes,Request);
	_ ->
	    rest_helper:error(html_adaptor,'HEAD',Url,Request,"Illegal resource request")
    end;
react_to('POST',Url,Request) ->
    case rest_helper:split(Url) of
	{Resource,Ext} ->
	    case rest_helper:attributes_and_actor(Request,'POST') of
		{_,{annonymous}} ->
		    rest_helper:forbidden(Resource,Request,"You have to be logged in to create or update resources");
		{Attributes,Credentials} ->
		    rest_reactors:respond_to(adaptor(Ext,rest_helper:accepts(Request)),create,Resource,Credentials,Attributes,Request)
	    end;
	_ ->
	    rest_helper:error(html_adaptor,'HEAD',Url,Request,"Illegal resource request")
    end;
react_to('PUT',Url,Request) ->
    case rest_helper:split(Url) of
	{Resource,Ext} ->
	    case rest_helper:attributes_and_actor(Request,'POST') of
		{_,{annonymous}} ->
		    rest_helper:forbidden(Resource,Request,"You have to be logged in to create or update resources");
		{Attributes,Credentials} ->
		    rest_reactors:respond_to(adaptor(Ext,rest_helper:accepts(Request)),update,Resource,Credentials,Attributes,Request)
	    end;
	_ ->
	    rest_helper:error(html_adaptor,'HEAD',Url,Request,"Illegal resource request")
    end;
react_to('DELETE',Url,Request) ->
    case rest_helper:split(Url) of
	{Resource,Ext} ->
	    case rest_helper:attributes_and_actor(Request,'POST') of
		{_,{annonymous}} ->
		    rest_helper:forbidden(Resource,Request,"You have to be logged in to delete resources");
		{Attributes,Credentials} ->
		    rest_reactors:respond_to(adaptor(Ext,rest_helper:accepts(Request)),delete,Resource,Credentials,Attributes,Request)
	    end;
	_ ->
	    rest_helper:error(html_adaptor,'HEAD',Url,Request,"Illegal resource request")
    end;

%% Catch all, error default
react_to(Method,Resource,Request) ->
    Request:respond({501, [], atom_to_list(Method) ++ " not supported for " ++ Resource}).

%% Content & Type Adaptors
adaptor("atom" ++ _, _Accept) ->
    atom_adaptor;
adaptor("js" ++ _, _Accept) ->
    json_adaptor;
adaptor("html" ++ _, _Accept) ->
    html_adaptor;
adaptor("xhtml" ++ _, _Accept) ->
    xhtml_adaptor;
adaptor("csv" ++ _, _Accept) ->
    csv_adaptor;
adaptor(_, "application/atom+xml" ++ _) ->
    atom_adaptor;
adaptor(_, "application/xml" ++ _) ->
    atom_adaptor;
adaptor(_, "application/json" ++ _) ->
    json_adaptor;
adaptor(_, "application/xhtml+xml" ++ _) ->
    html_adaptor;
adaptor(_, "text/html" ++ _) ->
    html_adaptor;
adaptor(_, "text/plain" ++ _) ->
    csv_adaptor;
adaptor(_, _Accept) ->
    html_adaptor.

error(Error) ->
    error_logger:error_msg("Actor server - Says Whoops ~p~n",[Error]),
    Error.
