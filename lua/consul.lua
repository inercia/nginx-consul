local math          = require "math"
local cjson         = require "cjson"
local consul_client = require "resty.consul"
local cache         = ngx.shared.lb

local _M = {
    _VERSION = '0.1'
}

local RETRY_INTERVAL = 5

if not ngx.config
   or not ngx.config.ngx_lua_version
   or ngx.config.ngx_lua_version < 9005
then
    error("ngx_lua 0.9.5+ required")
end

local abort
abort = function (reason, code)
    ngx.status = code
    ngx.log(ngx.ERR, reason)
    return code
end

--
-- Establish a connection to a Consul server and watch a name
--
local do_watch
do_watch = function (premature, name, consul_addr, consul_port)
    if premature then
        return
    end

    ngx.log(ngx.DEBUG, "connecting to '", consul_addr, ":", consul_port, "' for watching '", name, "'")
    local consul = consul_client:new({
        host = consul_addr,
        port = consul_port
    })

    key     = "/catalog/service/" .. name
    index   = 0
    args    = {}

    ngx.log(ngx.DEBUG, "connected to '", consul_addr, ":", consul_port, "': watching ", key)

    -- loop forever, receiving updates
    while true do
        data, err = consul:get(key, args)
        if not data then
            ngx.log(ngx.ERR, "no data received")
            if err ~= nil then
                ngx.log(ngx.ERR, "connection to '", consul_addr, ":", consul_port, "' aborted: ", err)
                break
            else
                ngx.log(ngx.ERR, "continuing")
            end
        else
            headers = err
            index   = headers[3]
            if #data > 0 then
                ngx.log(ngx.DEBUG, "received ", #data, " node(s) [vers:", index, "]")

                -- save the data exactly as we receive it in the cache
                local ok, err = cache:set(name, cjson.encode(data))
                if not ok then
                    ngx.log(ngx.ERR, "failed to update the cache: ", err)
                    break
                end
            end

            args = {
                index = index
            }
        end
    end

    local ok, err = ngx.timer.at(RETRY_INTERVAL, do_watch, name, consul_addr, consul_port)
    if not ok then
        ngx.log(ngx.ERR, "failed to reschedule watcher", err)
        return
    end
end

--
-- start watching a name
--
function _M.watch_name(self, name, consul_addr, consul_port)
    local ok, err = ngx.timer.at(0, do_watch, name, consul_addr, consul_port)
    if not ok then
        return nil, "failed to create timer: " .. err
    end
    
    return true
end

--
-- return a random upstream from the cache
--
function _M.random_upstream(self, name)
    math.randomseed(os.time())

    ngx.log(ngx.DEBUG, "getting random upstream for '", name, "'")
    cached, err = cache:get(name)
    if cached then
        local nodes         = cjson.decode(cached)
        local upstream_idx  = math.random(1, #nodes)
        local upstream      = nodes[upstream_idx]["Address"] .. ":" .. nodes[upstream_idx]["ServicePort"]

        ngx.log(ngx.DEBUG, "rand(1,", #nodes, ") = ", upstream_idx, " = ", upstream)
        return upstream
    else
        ngx.log(ngx.ERR, "no upstream servers in cache")
        return nil, abort("Internal routing error", 500)
    end
end

return _M
