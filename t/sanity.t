# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua::Stream;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

$ENV{TEST_NGINX_MY_INIT_CONFIG} = <<_EOC_;
lua_package_path "t/lib/?.lua;;";
_EOC_

no_long_string();
#no_diff();
#log_level 'warn';

run_tests();

__DATA__

=== TEST 1: get upstream names
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG

    upstream foo.com:1234 {
        server 127.0.0.1:1234;
    }

    upstream bar {
        server 127.0.0.2:1234;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local us = upstream.get_upstreams()
        for _, u in ipairs(us) do
            ngx.say(u)
        end
        ngx.say("done")
    }
--- stream_response
foo.com:1234
bar
done
--- no_error_log
[error]



=== TEST 2: get upstream names (no upstream)
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local us = upstream.get_upstreams()
        for _, u in ipairs(us) do
            ngx.say(u)
        end
        ngx.say("done")
    }
--- stream_response
done
--- no_error_log
[error]



=== TEST 3: get servers
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream foo.com:1234 {
        server 127.0.0.1:1234 fail_timeout=53 weight=4 max_fails=100;
        server 127.0.0.2:1234 backup;
    }

    upstream bar {
        server 127.0.0.2:80;

    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        for _, host in pairs{ "foo.com:1234", "bar", "blah" } do
            local srvs, err = upstream.get_servers(host)
            if not srvs then
                ngx.say("failed to get servers: ", err)
            else
                ngx.say(host, ": ", ljson.encode(srvs))
            end
        end
    }
--- stream_response
foo.com:1234: [{"addr":"127.0.0.1:1234","fail_timeout":53,"max_fails":100,"name":"127.0.0.1:1234","weight":4},{"addr":"127.0.0.2:1234","backup":true,"fail_timeout":10,"max_fails":1,"name":"127.0.0.2:1234","weight":1}]
bar: [{"addr":"127.0.0.2:80","fail_timeout":10,"max_fails":1,"name":"127.0.0.2:80","weight":1}]
failed to get servers: upstream not found
--- no_error_log
[error]



=== TEST 4: sample in README
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream foo.com {
        server 127.0.0.1:80 fail_timeout=53 weight=4 max_fails=100;
        server 127.0.0.2:81;
    }

    upstream bar {
        server 127.0.0.2:80;
    }

--- stream_server_config
    content_by_lua_block {
        local concat = table.concat
        local upstream = require "ngx.upstream"
        local get_servers = upstream.get_servers
        local get_upstreams = upstream.get_upstreams

        local us = get_upstreams()
        for _, u in ipairs(us) do
            ngx.say("upstream ", u, ":")
            local srvs, err = get_servers(u)
            if not srvs then
                ngx.say("failed to get servers in upstream ", u)
            else
                for _, srv in ipairs(srvs) do
                    local first = true
                    for k, v in pairs(srv) do
                        if first then
                            first = false
                            ngx.print("    ")
                        else
                            ngx.print(", ")
                        end
                        if type(v) == "table" then
                            ngx.print(k, " = {", concat(v, ", "), "}")
                        else
                            ngx.print(k, " = ", v)
                        end
                    end
                    ngx.say()
                end
            end
        end
    }
--- stream_response
upstream foo.com:
    addr = 127.0.0.1:80, weight = 4, fail_timeout = 53, name = 127.0.0.1:80, max_fails = 100
    addr = 127.0.0.2:81, weight = 1, fail_timeout = 10, name = 127.0.0.2:81, max_fails = 1
upstream bar:
    addr = 127.0.0.2:80, weight = 1, fail_timeout = 10, name = 127.0.0.2:80, max_fails = 1
--- no_error_log
[error]



=== TEST 5: multi-peer servers
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream test {
        server multi-ip-test.openresty.com:80;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        local srvs, err = upstream.get_servers("test")
        if not srvs then
            ngx.say("failed to get test ", err)
            return
        end
        ngx.say(ljson.encode(srvs))
    }
--- stream_response_like
^\[\{"addr":\["\d{1,3}(?:\.\d{1,3}){3}:80"(?:,"\d{1,3}(?:\.\d{1,3}){3}:80")+\],"fail_timeout":10,"max_fails":1,"name":"multi-ip-test\.openresty\.com:80","weight":1\}\]$
--- no_error_log
[error]



=== TEST 6: get primary peers: multi-peer servers
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream test {
        server multi-ip-test.openresty.com:80;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        local peers, err = upstream.get_primary_peers("test")
        if not peers then
            ngx.say("failed to get primary peers: ", err)
            return
        end
        ngx.say(ljson.encode(peers))
    }
--- stream_response_like
^\[\{"conns":0,"current_weight":0,"effective_weight":1,"fail_timeout":10,"fails":0,"id":0,"max_fails":1,"name":"\d{1,3}(?:\.\d{1,3}){3}:80","weight":1\}(?:,\{"conns":0,"current_weight":0,"effective_weight":1,"fail_timeout":10,"fails":0,"id":\d+,"max_fails":1,"name":"\d{1,3}(?:\.\d{1,3}){3}:80","weight":1\})+\]$
--- no_error_log
[error]



=== TEST 7: get primary peers
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream foo.com:1234 {
        server 127.0.0.6:80 fail_timeout=5 backup;
        server 127.0.0.1:80 fail_timeout=53 weight=4 max_fails=100;
        server 127.0.0.2:81;
    }

    upstream bar {
        server 127.0.0.2:80;
        server 127.0.0.3:80 backup;
        server 127.0.0.4:80 fail_timeout=23 weight=7 max_fails=200 backup;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        us = upstream.get_upstreams()
        for _, u in ipairs(us) do
            local peers, err = upstream.get_primary_peers(u)
            if not peers then
                ngx.say("failed to get peers: ", err)
                return
            end
            ngx.say(ljson.encode(peers))
        end
    }
--- stream_response
[{"conns":0,"current_weight":0,"effective_weight":4,"fail_timeout":53,"fails":0,"id":0,"max_fails":100,"name":"127.0.0.1:80","weight":4},{"conns":0,"current_weight":0,"effective_weight":1,"fail_timeout":10,"fails":0,"id":1,"max_fails":1,"name":"127.0.0.2:81","weight":1}]
[{"conns":0,"current_weight":0,"effective_weight":1,"fail_timeout":10,"fails":0,"id":0,"max_fails":1,"name":"127.0.0.2:80","weight":1}]
--- no_error_log
[error]



=== TEST 8: get backup peers
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream foo.com:1234 {
        server 127.0.0.6:80 fail_timeout=5 backup;
        server 127.0.0.1:80 fail_timeout=53 weight=4 max_fails=100;
        server 127.0.0.2:81;
    }

    upstream bar {
        server 127.0.0.2:80;
        server 127.0.0.3:80 backup;
        server 127.0.0.4:80 fail_timeout=23 weight=7 max_fails=200 backup;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        us = upstream.get_upstreams()
        for _, u in ipairs(us) do
            local peers, err = upstream.get_backup_peers(u)
            if not peers then
                ngx.say("failed to get peers: ", err)
                return
            end
            ngx.say(ljson.encode(peers))
        end
    }
--- stream_response
[{"conns":0,"current_weight":0,"effective_weight":1,"fail_timeout":5,"fails":0,"id":0,"max_fails":1,"name":"127.0.0.6:80","weight":1}]
[{"conns":0,"current_weight":0,"effective_weight":1,"fail_timeout":10,"fails":0,"id":0,"max_fails":1,"name":"127.0.0.3:80","weight":1},{"conns":0,"current_weight":0,"effective_weight":7,"fail_timeout":23,"fails":0,"id":1,"max_fails":200,"name":"127.0.0.4:80","weight":7}]
--- no_error_log
[error]



=== TEST 9: set primary peer down (0)
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream bar {
        server 127.0.0.2:80;
        server 127.0.0.3:80 backup;
        server 127.0.0.4:80 fail_timeout=23 weight=7 max_fails=200 backup;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        local u = "bar"
        local ok, err = upstream.set_peer_down(u, false, 0, true)
        if not ok then
            ngx.say("failed to set peer down: ", err)
            return
        end
        local peers, err = upstream.get_primary_peers(u)
        if not peers then
            ngx.say("failed to get peers: ", err)
            return
        end
        ngx.say(ljson.encode(peers))
    }
--- stream_response
[{"conns":0,"current_weight":0,"down":true,"effective_weight":1,"fail_timeout":10,"fails":0,"id":0,"max_fails":1,"name":"127.0.0.2:80","weight":1}]
--- no_error_log
[error]



=== TEST 10: set primary peer down (1, bad index)
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream bar {
        server 127.0.0.2:80;
        server 127.0.0.3:80 backup;
        server 127.0.0.4:80 fail_timeout=23 weight=7 max_fails=200 backup;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        local u = "bar"
        local ok, err = upstream.set_peer_down(u, false, 1, true)
        if not ok then
            ngx.say("failed to set peer down: ", err)
            return
        end
        local peers, err = upstream.get_primary_peers(u)
        if not peers then
            ngx.say("failed to get peers: ", err)
            return
        end
        ngx.say(ljson.encode(peers))
    }
--- stream_response
failed to set peer down: bad peer id
--- no_error_log
[error]



=== TEST 11: set backup peer down (index 0)
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream bar {
        server 127.0.0.2:80;
        server 127.0.0.3:80 backup;
        server 127.0.0.4:80 fail_timeout=23 weight=7 max_fails=200 backup;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        local u = "bar"
        local ok, err = upstream.set_peer_down(u, true, 0, true)
        if not ok then
            ngx.say("failed to set peer down: ", err)
            return
        end
        local peers, err = upstream.get_backup_peers(u)
        if not peers then
            ngx.say("failed to get peers: ", err)
            return
        end
        ngx.say(ljson.encode(peers))
    }
--- stream_response
[{"conns":0,"current_weight":0,"down":true,"effective_weight":1,"fail_timeout":10,"fails":0,"id":0,"max_fails":1,"name":"127.0.0.3:80","weight":1},{"conns":0,"current_weight":0,"effective_weight":7,"fail_timeout":23,"fails":0,"id":1,"max_fails":200,"name":"127.0.0.4:80","weight":7}]
--- no_error_log
[error]



=== TEST 12: set backup peer down (toggle twice, index 0)
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream bar {
        server 127.0.0.2:80;
        server 127.0.0.3:80 backup;
        server 127.0.0.4:80 fail_timeout=23 weight=7 max_fails=200 backup;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        local u = "bar"
        local ok, err = upstream.set_peer_down(u, true, 0, true)
        if not ok then
            ngx.say("failed to set peer down: ", err)
            return
        end
        local ok, err = upstream.set_peer_down(u, true, 0, false)
        if not ok then
            ngx.say("failed to set peer down: ", err)
            return
        end
            local peers, err = upstream.get_backup_peers(u)
        if not peers then
            ngx.say("failed to get peers: ", err)
            return
        end
        ngx.say(ljson.encode(peers))
    }
--- stream_response
[{"conns":0,"current_weight":0,"effective_weight":1,"fail_timeout":10,"fails":0,"id":0,"max_fails":1,"name":"127.0.0.3:80","weight":1},{"conns":0,"current_weight":0,"effective_weight":7,"fail_timeout":23,"fails":0,"id":1,"max_fails":200,"name":"127.0.0.4:80","weight":7}]
--- no_error_log
[error]



=== TEST 13: set backup peer down (index 1)
--- stream_config
    $TEST_NGINX_MY_INIT_CONFIG
    upstream bar {
        server 127.0.0.2:80;
        server 127.0.0.3:80 backup;
        server 127.0.0.4:80 fail_timeout=23 weight=7 max_fails=200 backup;
    }
--- stream_server_config
    content_by_lua_block {
        local upstream = require "ngx.upstream"
        local ljson = require "ljson"
        local u = "bar"
        local ok, err = upstream.set_peer_down(u, true, 1, true)
        if not ok then
            ngx.say("failed to set peer down: ", err)
            return
        end
            local peers, err = upstream.get_backup_peers(u)
        if not peers then
            ngx.say("failed to get peers: ", err)
            return
        end
        ngx.say(ljson.encode(peers))
    }
--- stream_response
[{"conns":0,"current_weight":0,"effective_weight":1,"fail_timeout":10,"fails":0,"id":0,"max_fails":1,"name":"127.0.0.3:80","weight":1},{"conns":0,"current_weight":0,"down":true,"effective_weight":7,"fail_timeout":23,"fails":0,"id":1,"max_fails":200,"name":"127.0.0.4:80","weight":7}]
--- no_error_log
[error]
