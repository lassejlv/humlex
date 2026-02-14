pub mod anthropic;
pub mod gemini;
pub mod kimi;
pub mod openai;
pub mod retry;

use std::pin::Pin;

use async_trait::async_trait;
use bytes::Bytes;
use futures_util::Stream;
use serde_json::Value;

use crate::error::GatewayError;

pub type ProviderStream = Pin<Box<dyn Stream<Item = Result<Bytes, GatewayError>> + Send>>;

#[async_trait]
pub trait ProviderSdk: Send + Sync {
    async fn fetch_models(&self, api_key: &str) -> Result<Value, GatewayError>;
    async fn generate_text(&self, api_key: &str, request: Value) -> Result<Value, GatewayError>;
    async fn stream_text(
        &self,
        api_key: &str,
        request: Value,
    ) -> Result<ProviderStream, GatewayError>;
}
