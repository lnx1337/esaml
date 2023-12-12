%% esaml - SAML for erlang
%%
%% Copyright (c) 2013, Alex Wilson and the University of Queensland
%% All rights reserved.
%%
%% Distributed subject to the terms of the 2-clause BSD license, see
%% the LICENSE file in the root of the distribution.

%% @doc SAML HTTP binding handlers
-module(esaml_binding).

-export([decode_response/2, encode_http_redirect/4, external_uri_quote/1, encode_http_post/3, encode_http_post/4]).

-include_lib("xmerl/include/xmerl.hrl").
-define(deflate, <<"urn:oasis:names:tc:SAML:2.0:bindings:URL-Encoding:DEFLATE">>).

-type uri() :: binary() | string().
-type html_doc() :: binary().
-type xml() :: #xmlElement{} | #xmlDocument{}.

%% @private
-spec xml_payload_type(xml()) -> binary().
xml_payload_type(Xml) ->
    case Xml of
        #xmlDocument{content = [#xmlElement{name = Atom}]} ->
            case lists:suffix("Response", atom_to_list(Atom)) of
                true -> <<"SAMLResponse">>;
                _ -> <<"SAMLRequest">>
            end;
        #xmlElement{name = Atom} ->
            case lists:suffix("Response", atom_to_list(Atom)) of
                true -> <<"SAMLResponse">>;
                _ -> <<"SAMLRequest">>
            end;
        _ -> <<"SAMLRequest">>
    end.

%% @doc Unpack and parse a SAMLResponse with given encoding
-spec decode_response(SAMLEncoding :: binary(), SAMLResponse :: binary()) -> #xmlDocument{}.
decode_response(?deflate, SAMLResponse) ->
	XmlData = binary_to_list(zlib:unzip(base64:decode(SAMLResponse))),
	{Xml, _} = xmerl_scan:string(XmlData, [{namespace_conformant, true}]),
    Xml;
decode_response(_, SAMLResponse) ->
	Data = base64:decode(SAMLResponse),
    XmlData = case (catch zlib:unzip(Data)) of
        {'EXIT', _} -> binary_to_list(Data);
        Bin -> binary_to_list(Bin)
    end,
	{Xml, _} = xmerl_scan:string(XmlData, [{namespace_conformant, true}]),
    Xml.

%% @doc Encode a SAMLRequest (or SAMLResponse) as an HTTP-Redirect binding
%%
%% Returns the URI that should be the target of redirection.
% -spec encode_http_redirect(IDPTarget :: uri(), SignedXml :: xml(), Username :: undefined | string(), RelayState :: binary()) -> uri().
% encode_http_redirect(IdpTarget, SignedXml, Username, RelayState) ->
%   Type = xml_payload_type(SignedXml),
%   Req = lists:flatten(xmerl:export([SignedXml], xmerl_xml)),

%   QueryList = [
%                {"SAMLEncoding", ?deflate},
%                {Type, uri_string:quote(base64:encode_to_string(zlib:zip(Req)))},
%                {"RelayState", uri_string:normalize(binary_to_list(RelayState))}
%               ],
%   QueryParamStr = uri_string:compose_query(QueryList),
%   FirstParamDelimiter = case lists:member($?, IdpTarget) of true -> "&"; false -> "?" end,
%   Username_Part = redirect_username_part(Username),

%   iolist_to_binary([IdpTarget, FirstParamDelimiter, QueryParamStr | Username_Part]).

% redirect_username_part(Username) when is_binary(Username), size(Username) > 0 ->
%   ["&", uri_string:compose_query([{"username", uri_string:normalize(binary_to_list(Username))}])];
% redirect_username_part(_Other) -> [].

-spec encode_http_redirect(IDPTarget :: uri(), SignedXml :: xml(), Username :: undefined | string(), RelayState :: binary()) -> uri().
encode_http_redirect(IdpTarget, SignedXml, Username, RelayState) ->
  Type = xml_payload_type(SignedXml),
  Req = lists:flatten(xmerl:export([SignedXml], xmerl_xml)),
  
  % Codificar usando el endpoint externo
  EncodedReq = quote_base64(base64:encode_to_string(zlib:zip(Req))),

  QueryList = [
               {"SAMLEncoding", ?deflate},
               {Type, EncodedReq},
               {"RelayState", uri_string:normalize(binary_to_list(RelayState))}
              ],
  QueryParamStr = uri_string:compose_query(QueryList),
  FirstParamDelimiter = case lists:member($?, IdpTarget) of true -> "&"; false -> "?" end,
  Username_Part = redirect_username_part(Username),

  iolist_to_binary([IdpTarget, FirstParamDelimiter, QueryParamStr | Username_Part]).

redirect_username_part(Username) when is_binary(Username), size(Username) > 0 ->
  ["&", uri_string:compose_query([{"username", uri_string:normalize(binary_to_list(Username))}])];
redirect_username_part(_Other) -> [].

quote_base64(Base64String) ->
  lists:map(fun replace_unsafe_chars/1, Base64String).
  replace_unsafe_chars($+) -> $-;  % Reemplaza '+' por '-'
  replace_unsafe_chars($/) -> $_;  % Reemplaza '/' por '_'
  replace_unsafe_chars(Char) -> Char.

% Función para realizar la codificación de la URL utilizando el endpoint externo
external_uri_quote(String) ->
  Url = "https://backend-sandbox-dnxtra.addabra.com/api/v1/erl/quote",
  String2 = "test",
  ContentType = "application/json",
  Body = io_lib:format("{\"quote_string\": \"~s\"}", [String2]),
  Headers = [{"Content-Type", ContentType}],

  % Imprimir el URL y el cuerpo de la solicitud
  io:format("String body: ~s~n", [String]),
  io:format("Calling endpoint: ~s~n", [Url]),
  io:format("Request body: ~s~n", [Body]),

  httpc:request(post, {Url, [], ContentType, "{\"quote_string\":\"" ++ String2 ++ "\"}"}, [], []),
  httpc:request(post, {Url, [], ContentType, "{'quote_string':'"++ String++"'}"}, [], []),
  Response = httpc:request(post, {Url, [], ContentType, "{'quote_string':'"++ String++"'}"}, [], []),
  case Response of
    {ok, {{_, 200, _}, _, RespBody}} ->
      % Procesar la respuesta JSON y extraer el campo 'data'
      {ok, JSON} = jsx:decode(RespBody, [return_maps]),
      maps:get("data", JSON);
    {ok, {{_, StatusCode, StatusMessage}, _, RespBody}} ->
      % Manejar otros códigos de estado HTTP
      io:format("Error: HTTP Status ~p ~p, Response Body: ~p~n", [StatusCode, StatusMessage, RespBody]),
      error({http_error, StatusCode, RespBody});
    {error, Reason} ->
      % Manejar el error de conexión
      error(Reason)
  end.

%% @doc Encode a SAMLRequest (or SAMLResponse) as an HTTP-POST binding
%%
%% Returns the HTML document to be sent to the browser, containing a
%% form and javascript to automatically submit it.
-spec encode_http_post(IDPTarget :: uri(), SignedXml :: xml(), RelayState :: binary()) -> html_doc().
encode_http_post(IdpTarget, SignedXml, RelayState) ->
    encode_http_post(IdpTarget, SignedXml, RelayState, <<>>).

-spec encode_http_post(IDPTarget :: uri(), SignedXml :: xml(), RelayState :: binary(), Nonce :: binary()) -> html_doc().
encode_http_post(IdpTarget, SignedXml, RelayState, Nonce) when is_binary(Nonce) ->
    Type = xml_payload_type(SignedXml),
	Req = lists:flatten(xmerl:export([SignedXml], xmerl_xml)),
    generate_post_html(Type, IdpTarget, base64:encode(Req), RelayState, Nonce).

generate_post_html(Type, Dest, Req, RelayState, Nonce) ->
    NonceFragment = case Nonce of
        <<>> -> <<>>;
        _ -> [<<"nonce=\"">>, Nonce, <<"\"">>]
    end,
    iolist_to_binary([<<"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">
<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">
<head>
<meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\" />
<title>POST data</title>
</head>
<body>
<script ">>,NonceFragment,<<">
document.addEventListener('DOMContentLoaded', function () {
document.getElementById('saml-req-form').submit();
});
</script>
<noscript>
<p><strong>Note:</strong> Since your browser does not support JavaScript, you must press the button below once to proceed.</p>
</noscript>
<form id=\"saml-req-form\" method=\"post\" action=\"">>,Dest,<<"\">
<input type=\"hidden\" name=\"">>,Type,<<"\" value=\"">>,Req,<<"\" />
<input type=\"hidden\" name=\"RelayState\" value=\"">>,RelayState,<<"\" />
<noscript><input type=\"submit\" value=\"Submit\" /></noscript>
</form>
</body>
</html>">>]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-endif.
