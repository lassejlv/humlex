use std::io;

use axum::Json;
use axum::body::Body;
use axum::extract::Query;
use axum::extract::State;
use axum::extract::rejection::JsonRejection;
use axum::http::header::{CACHE_CONTROL, CONNECTION, CONTENT_TYPE};
use axum::http::{HeaderMap, HeaderName, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use futures_util::StreamExt;
use serde_json::{Value, json};

use crate::auth::{extract_bearer, resolve_provider_api_key, validate_gateway_key};
use crate::error::GatewayError;
use crate::http::responses as responses_api;
use crate::http::state::AppState;
use crate::providers::registry::ProviderKind;

#[derive(serde::Deserialize)]
pub struct ModelsQuery {
    provider: Option<String>,
}

pub async fn root() -> Json<Value> {
    Json(json!({
        "name": "gateway",
        "status": "ok"
    }))
}

pub async fn healthz() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

pub async fn list_models(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<ModelsQuery>,
) -> Result<Json<Value>, GatewayError> {
    let token = extract_bearer(&headers)?;
    validate_gateway_key(state.config.as_ref(), &token)?;

    if let Some(provider_name) = query.provider.as_deref() {
        let kind = ProviderKind::parse(provider_name).ok_or_else(|| {
            GatewayError::BadRequest(
                "provider must be one of: openai, anthropic, gemini, kimi".to_string(),
            )
        })?;

        let provider = state.registry.provider(kind);
        let api_key = resolve_provider_api_key(state.config.as_ref(), &token, kind)?;
        let models = provider.fetch_models(&api_key).await?;
        return Ok(Json(models));
    }

    let mut data = Vec::new();
    let mut first_error = None;

    for (kind, provider) in state.registry.all() {
        let api_key = resolve_provider_api_key(state.config.as_ref(), &token, kind)?;
        match provider.fetch_models(&api_key).await {
            Ok(models) => {
                if let Some(entries) = models.get("data").and_then(Value::as_array) {
                    data.extend(entries.iter().cloned());
                }
            }
            Err(error) => {
                if first_error.is_none() {
                    first_error = Some(error);
                }
            }
        }
    }

    if data.is_empty() {
        return Err(first_error.unwrap_or_else(|| {
            GatewayError::BadRequest("No models available for the provided API key".to_string())
        }));
    }

    Ok(Json(json!({
        "object": "list",
        "data": data,
    })))
}

pub async fn chat_completions(
    State(state): State<AppState>,
    headers: HeaderMap,
    payload: Result<Json<Value>, JsonRejection>,
) -> Result<Response, GatewayError> {
    let token = extract_bearer(&headers)?;
    let Json(mut payload) =
        payload.map_err(|_| GatewayError::BadRequest("Invalid JSON request body".to_string()))?;
    let model = validate_chat_completion_request(&payload)?;
    let (kind, upstream_model) = ProviderKind::resolve_model(&model);
    payload["model"] = json!(upstream_model);
    let api_key = resolve_provider_api_key(state.config.as_ref(), &token, kind)?;

    let stream = payload
        .get("stream")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let provider = state.registry.provider(kind);

    if stream {
        let upstream_stream = provider.stream_text(&api_key, payload).await?;
        let body_stream =
            upstream_stream.map(|item| item.map_err(|error| io::Error::other(error.to_string())));

        let mut response = Response::new(Body::from_stream(body_stream));
        *response.status_mut() = StatusCode::OK;
        response
            .headers_mut()
            .insert(CONTENT_TYPE, HeaderValue::from_static("text/event-stream"));
        response
            .headers_mut()
            .insert(CACHE_CONTROL, HeaderValue::from_static("no-cache"));
        response
            .headers_mut()
            .insert(CONNECTION, HeaderValue::from_static("keep-alive"));
        response.headers_mut().insert(
            HeaderName::from_static("x-accel-buffering"),
            HeaderValue::from_static("no"),
        );

        return Ok(response);
    }

    let response = provider.generate_text(&api_key, payload).await?;
    Ok(Json(response).into_response())
}

pub async fn responses(
    State(state): State<AppState>,
    headers: HeaderMap,
    payload: Result<Json<Value>, JsonRejection>,
) -> Result<Response, GatewayError> {
    let token = extract_bearer(&headers)?;
    let Json(payload) =
        payload.map_err(|_| GatewayError::BadRequest("Invalid JSON request body".to_string()))?;

    let mut chat_payload = responses_api::build_chat_request(&payload)?;
    let model = validate_chat_completion_request(&chat_payload)?;
    let (kind, upstream_model) = ProviderKind::resolve_model(&model);
    chat_payload["model"] = json!(upstream_model);
    let api_key = resolve_provider_api_key(state.config.as_ref(), &token, kind)?;

    let stream = chat_payload
        .get("stream")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let provider = state.registry.provider(kind);

    if stream {
        let chat_stream = provider.stream_text(&api_key, chat_payload).await?;
        let response_stream = responses_api::stream_responses_from_chat_stream(chat_stream);
        let body_stream =
            response_stream.map(|item| item.map_err(|error| io::Error::other(error.to_string())));

        let mut response = Response::new(Body::from_stream(body_stream));
        *response.status_mut() = StatusCode::OK;
        response
            .headers_mut()
            .insert(CONTENT_TYPE, HeaderValue::from_static("text/event-stream"));
        response
            .headers_mut()
            .insert(CACHE_CONTROL, HeaderValue::from_static("no-cache"));
        response
            .headers_mut()
            .insert(CONNECTION, HeaderValue::from_static("keep-alive"));
        response.headers_mut().insert(
            HeaderName::from_static("x-accel-buffering"),
            HeaderValue::from_static("no"),
        );

        return Ok(response);
    }

    let chat_response = provider.generate_text(&api_key, chat_payload).await?;
    let response = responses_api::response_from_chat_completion(&chat_response);
    Ok(Json(response).into_response())
}

fn validate_chat_completion_request(payload: &Value) -> Result<String, GatewayError> {
    let model = payload.get("model").and_then(Value::as_str);
    if model.is_none() {
        return Err(GatewayError::BadRequest(
            "The request body must include a model".to_string(),
        ));
    }

    let messages = payload.get("messages").and_then(Value::as_array);
    if messages.is_none() {
        return Err(GatewayError::BadRequest(
            "The request body must include messages".to_string(),
        ));
    }

    Ok(model.unwrap_or_default().to_string())
}
