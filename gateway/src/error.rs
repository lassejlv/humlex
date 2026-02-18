use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use serde_json::Value;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum GatewayError {
    #[error("Unauthorized: {0}")]
    Unauthorized(String),
    #[error("Bad request: {0}")]
    BadRequest(String),
    #[error("Upstream request failed")]
    Upstream { status: StatusCode, body: String },
    #[error("Transport error: {0}")]
    Transport(#[from] reqwest::Error),
    #[error("Internal error: {0}")]
    Internal(String),
}

impl GatewayError {
    pub fn upstream(status: StatusCode, body: String) -> Self {
        Self::Upstream { status, body }
    }
}

impl IntoResponse for GatewayError {
    fn into_response(self) -> Response {
        match self {
            Self::Unauthorized(message) => {
                error_response(StatusCode::UNAUTHORIZED, message, "authentication_error")
                    .into_response()
            }
            Self::BadRequest(message) => {
                error_response(StatusCode::BAD_REQUEST, message, "invalid_request_error")
                    .into_response()
            }
            Self::Upstream { status, body } => {
                if let Ok(value) = serde_json::from_str::<Value>(&body) {
                    return (status, Json(value)).into_response();
                }

                let message = if body.trim().is_empty() {
                    format!("Upstream provider returned {}", status)
                } else {
                    body
                };
                error_response(status, message, "upstream_error").into_response()
            }
            Self::Transport(_) => error_response(
                StatusCode::BAD_GATEWAY,
                "Failed to reach upstream provider".to_string(),
                "upstream_error",
            )
            .into_response(),
            Self::Internal(message) => {
                error_response(StatusCode::INTERNAL_SERVER_ERROR, message, "internal_error")
                    .into_response()
            }
        }
    }
}

fn error_response(
    status: StatusCode,
    message: String,
    error_type: &'static str,
) -> (StatusCode, Json<OpenAiErrorResponse>) {
    (
        status,
        Json(OpenAiErrorResponse {
            error: OpenAiError {
                message,
                error_type: error_type.to_string(),
                param: None,
                code: None,
            },
        }),
    )
}

#[derive(Debug, Serialize)]
struct OpenAiErrorResponse {
    error: OpenAiError,
}

#[derive(Debug, Serialize)]
struct OpenAiError {
    message: String,
    #[serde(rename = "type")]
    error_type: String,
    param: Option<String>,
    code: Option<String>,
}
