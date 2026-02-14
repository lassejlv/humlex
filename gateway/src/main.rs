mod auth;
mod config;
mod error;
mod http;
mod providers;
mod sdk;

use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use axum::routing::{get, post};
use config::Config;
use http::handlers::{chat_completions, doc, healthz, list_models, providers, responses, root};
use http::state::AppState;
use providers::registry::ProviderRegistry;
use sdk::anthropic::AnthropicProvider;
use sdk::azure_openai::AzureOpenAiProvider;
use sdk::gemini::GeminiProvider;
use sdk::kimi::KimiProvider;
use sdk::openai::OpenAiProvider;
use sdk::retry::RetryPolicy;
use tracing::info;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();

    let config = Config::from_env();
    let retry_policy = RetryPolicy::new(
        config.upstream_max_retries,
        config.upstream_retry_base_delay_ms,
    );

    let openai_client = reqwest::Client::builder()
        .timeout(Duration::from_secs(config.request_timeout_secs))
        .build()
        .expect("failed to build http client");

    let openai_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.openai_base_url.clone(),
        retry_policy,
    ));
    let anthropic_provider = Arc::new(AnthropicProvider::new(
        openai_client.clone(),
        config.anthropic_base_url.clone(),
        retry_policy,
    ));
    let gemini_provider = Arc::new(GeminiProvider::new(
        openai_client.clone(),
        config.gemini_base_url.clone(),
        retry_policy,
    ));
    let kimi_provider = Arc::new(KimiProvider::new(
        openai_client.clone(),
        config.kimi_base_url.clone(),
        retry_policy,
    ));
    let openrouter_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.openrouter_base_url.clone(),
        retry_policy,
    ));
    let vercel_ai_gateway_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.vercel_ai_gateway_base_url.clone(),
        retry_policy,
    ));
    let groq_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.groq_base_url.clone(),
        retry_policy,
    ));
    let deepseek_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.deepseek_base_url.clone(),
        retry_policy,
    ));
    let xai_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.xai_base_url.clone(),
        retry_policy,
    ));
    let mistral_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.mistral_base_url.clone(),
        retry_policy,
    ));
    let cohere_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.cohere_base_url.clone(),
        retry_policy,
    ));
    let azure_openai_provider = Arc::new(AzureOpenAiProvider::new(
        openai_client.clone(),
        config.azure_openai_base_url.clone(),
        retry_policy,
    ));
    let aws_bedrock_provider = Arc::new(OpenAiProvider::new(
        openai_client.clone(),
        config.aws_bedrock_base_url.clone(),
        retry_policy,
    ));
    let vertex_ai_provider = Arc::new(OpenAiProvider::new(
        openai_client,
        config.vertex_ai_base_url.clone(),
        retry_policy,
    ));
    let registry = Arc::new(ProviderRegistry::new(
        openai_provider,
        anthropic_provider,
        gemini_provider,
        kimi_provider,
        openrouter_provider,
        vercel_ai_gateway_provider,
        groq_provider,
        deepseek_provider,
        xai_provider,
        mistral_provider,
        cohere_provider,
        azure_openai_provider,
        aws_bedrock_provider,
        vertex_ai_provider,
    ));
    let state = AppState::new(registry, Arc::new(config.clone()));

    let app = Router::new()
        .route("/", get(root))
        .route("/doc", get(doc))
        .route("/providers", get(providers))
        .route("/status", get(healthz))
        .route("/healthz", get(healthz))
        .route("/v1/models", get(list_models))
        .route("/v1/chat/completions", post(chat_completions))
        .route("/v1/responses", post(responses))
        .with_state(state);

    let addr = config.bind_addr();
    info!(%addr, "gateway listening");
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .expect("failed to bind tcp listener");
    axum::serve(listener, app).await.expect("server failed");
}
