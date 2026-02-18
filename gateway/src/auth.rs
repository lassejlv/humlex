use axum::http::HeaderMap;

use crate::config::Config;
use crate::error::GatewayError;
use crate::providers::registry::ProviderKind;

pub fn extract_bearer(headers: &HeaderMap) -> Result<String, GatewayError> {
    let authorization = headers
        .get(axum::http::header::AUTHORIZATION)
        .ok_or_else(|| GatewayError::Unauthorized("Missing authorization header".to_string()))?;

    let authorization = authorization
        .to_str()
        .map_err(|_| GatewayError::Unauthorized("Invalid authorization header".to_string()))?;

    let token = authorization.strip_prefix("Bearer ").ok_or_else(|| {
        GatewayError::Unauthorized("Authorization must use Bearer token".to_string())
    })?;

    if token.trim().is_empty() {
        return Err(GatewayError::Unauthorized(
            "Bearer token is empty".to_string(),
        ));
    }

    Ok(token.to_string())
}

pub fn validate_gateway_key(config: &Config, token: &str) -> Result<(), GatewayError> {
    if config.gateway_api_keys.is_empty() {
        return Ok(());
    }

    let is_allowed = config
        .gateway_api_keys
        .iter()
        .any(|configured_key| configured_key == token);

    if is_allowed {
        return Ok(());
    }

    Err(GatewayError::Unauthorized(
        "Invalid gateway API key".to_string(),
    ))
}

pub fn resolve_provider_api_key(
    config: &Config,
    token: &str,
    provider: ProviderKind,
) -> Result<String, GatewayError> {
    validate_gateway_key(config, token)?;

    let configured = match provider {
        ProviderKind::OpenAi => config.openai_api_key.clone(),
        ProviderKind::Anthropic => config.anthropic_api_key.clone(),
        ProviderKind::Gemini => config.gemini_api_key.clone(),
        ProviderKind::Kimi => config.kimi_api_key.clone(),
        ProviderKind::OpenRouter => config.openrouter_api_key.clone(),
        ProviderKind::VercelAiGateway => config.vercel_ai_gateway_api_key.clone(),
        ProviderKind::Groq => config.groq_api_key.clone(),
        ProviderKind::DeepSeek => config.deepseek_api_key.clone(),
        ProviderKind::XAi => config.xai_api_key.clone(),
        ProviderKind::Mistral => config.mistral_api_key.clone(),
        ProviderKind::Cohere => config.cohere_api_key.clone(),
        ProviderKind::AzureOpenAi => config.azure_openai_api_key.clone(),
        ProviderKind::AwsBedrock => config.aws_bedrock_api_key.clone(),
        ProviderKind::VertexAi => config.vertex_ai_api_key.clone(),
    };

    Ok(configured.unwrap_or_else(|| token.to_string()))
}
