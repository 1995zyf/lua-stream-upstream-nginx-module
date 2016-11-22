/*
 * Copyright (C) Aleksey Konovkin (ZigzagAK)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <ngx_core.h>
#include <ngx_http.h>
#include <lauxlib.h>
#include "ngx_http_lua_api.h"


ngx_module_t ngx_stream_lua_upstream_http_api_module;


static ngx_int_t ngx_stream_lua_upstream_http_api_init(ngx_conf_t *cf);
extern int ngx_stream_lua_upstream_create_module(lua_State * L);


static ngx_http_module_t ngx_stream_lua_upstream_http_api_ctx = {
    NULL,                                      /* preconfiguration */
    ngx_stream_lua_upstream_http_api_init,     /* postconfiguration */
    NULL,                                      /* create main configuration */
    NULL,                                      /* init main configuration */
    NULL,                                      /* create server configuration */
    NULL,                                      /* merge server configuration */
    NULL,                                      /* create location configuration */
    NULL                                       /* merge location configuration */
};


ngx_module_t ngx_stream_lua_upstream_http_api_module = {
    NGX_MODULE_V1,
    &ngx_stream_lua_upstream_http_api_ctx,  /* module context */
    NULL,                                   /* module directives */
    NGX_HTTP_MODULE,                        /* module type */
    NULL,                                   /* init master */
    NULL,                                   /* init module */
    NULL,                                   /* init process */
    NULL,                                   /* init thread */
    NULL,                                   /* exit thread */
    NULL,                                   /* exit process */
    NULL,                                   /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_stream_lua_upstream_http_api_init(ngx_conf_t *cf)
{
    if (ngx_http_lua_add_package_preload(cf, "ngx.upstream.stream",
                                         ngx_stream_lua_upstream_create_module)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    return NGX_OK;
}
