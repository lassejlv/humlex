use async_trait::async_trait;
use axum::http::StatusCode;
use futures_util::StreamExt;
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE};
use serde_json::Value;

use crate::error::GatewayError;
use crate::sdk::retry::{RetryPolicy, send_with_retry};
use crate::sdk::{ProviderSdk, ProviderStream};

#[derive(Clone)]
pub struct GeminiProvider {
    client: reqwest::Client,
    base_url: String,
    retry_policy: RetryPolicy,
}

impl GeminiProvider {
    pub fn new(client: reqwest::Client, base_url: String, retry_policy: RetryPolicy) -> Self {
        Self {
            client,
            base_url,
            retry_policy,
        }
    }

    fn endpoint(&self, path: &str) -> String {
        format!("{}/{}", self.base_url, path.trim_start_matches('/'))
    }

    fn auth_header(api_key: &str) -> String {
        format!("Bearer {api_key}")
    }

    async fn parse_json_response(response: reqwest::Response) -> Result<Value, GatewayError> {
        let status = response.status();
        let text = response.text().await?;

        if !status.is_success() {
            return Err(GatewayError::upstream(status, text));
        }

        serde_json::from_str(&text)
            .map_err(|_| GatewayError::Internal("Upstream returned invalid JSON".to_string()))
    }
}

#[async_trait]
impl ProviderSdk for GeminiProvider {
    async fn fetch_models(&self, api_key: &str) -> Result<Value, GatewayError> {
        let response = send_with_retry(
            || {
                self.client
                    .get(self.endpoint("/models"))
                    .header(AUTHORIZATION, Self::auth_header(api_key))
            },
            self.retry_policy,
        )
        .await?;

        Self::parse_json_response(response).await
    }

    async fn generate_text(&self, api_key: &str, request: Value) -> Result<Value, GatewayError> {
        let response = send_with_retry(
            || {
                self.client
                    .post(self.endpoint("/chat/completions"))
                    .header(AUTHORIZATION, Self::auth_header(api_key))
                    .header(CONTENT_TYPE, "application/json")
                    .json(&request)
            },
            self.retry_policy,
        )
        .await?;

        Self::parse_json_response(response).await
    }

    async fn stream_text(
        &self,
        api_key: &str,
        mut request: Value,
    ) -> Result<ProviderStream, GatewayError> {
        request["stream"] = Value::Bool(true);

        let response = send_with_retry(
            || {
                self.client
                    .post(self.endpoint("/chat/completions"))
                    .header(AUTHORIZATION, Self::auth_header(api_key))
                    .header(CONTENT_TYPE, "application/json")
                    .json(&request)
            },
            self.retry_policy,
        )
        .await?;

        if response.status() != StatusCode::OK {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(GatewayError::upstream(status, body));
        }

        let stream = response
            .bytes_stream()
            .map(|chunk_result| chunk_result.map_err(GatewayError::from));

        Ok(Box::pin(stream))
    }
}
