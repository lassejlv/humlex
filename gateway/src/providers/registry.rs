use std::sync::Arc;

use crate::sdk::ProviderSdk;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProviderKind {
    OpenAi,
    Anthropic,
    Gemini,
    Kimi,
    OpenRouter,
    VercelAiGateway,
    Groq,
    DeepSeek,
    XAi,
    Mistral,
    Cohere,
    AzureOpenAi,
    AwsBedrock,
    VertexAi,
}

impl ProviderKind {
    pub fn id(self) -> &'static str {
        match self {
            Self::OpenAi => "openai",
            Self::Anthropic => "anthropic",
            Self::Gemini => "gemini",
            Self::Kimi => "kimi",
            Self::OpenRouter => "openrouter",
            Self::VercelAiGateway => "vercel",
            Self::Groq => "groq",
            Self::DeepSeek => "deepseek",
            Self::XAi => "xai",
            Self::Mistral => "mistral",
            Self::Cohere => "cohere",
            Self::AzureOpenAi => "azure",
            Self::AwsBedrock => "bedrock",
            Self::VertexAi => "vertex",
        }
    }

    pub fn all_kinds() -> [Self; 14] {
        [
            Self::OpenAi,
            Self::Anthropic,
            Self::Gemini,
            Self::Kimi,
            Self::OpenRouter,
            Self::VercelAiGateway,
            Self::Groq,
            Self::DeepSeek,
            Self::XAi,
            Self::Mistral,
            Self::Cohere,
            Self::AzureOpenAi,
            Self::AwsBedrock,
            Self::VertexAi,
        ]
    }

    pub fn resolve_model(model: &str) -> (Self, String) {
        if let Some(stripped) = model.strip_prefix("openai/") {
            return (Self::OpenAi, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("anthropic/") {
            return (Self::Anthropic, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("gemini/") {
            return (Self::Gemini, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("kimi/") {
            return (Self::Kimi, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("openrouter/") {
            return (Self::OpenRouter, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("vercel/") {
            return (Self::VercelAiGateway, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("groq/") {
            return (Self::Groq, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("deepseek/") {
            return (Self::DeepSeek, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("xai/") {
            return (Self::XAi, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("mistral/") {
            return (Self::Mistral, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("cohere/") {
            return (Self::Cohere, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("azure/") {
            return (Self::AzureOpenAi, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("bedrock/") {
            return (Self::AwsBedrock, stripped.to_string());
        }

        if let Some(stripped) = model.strip_prefix("vertex/") {
            return (Self::VertexAi, stripped.to_string());
        }

        let lower = model.to_ascii_lowercase();

        if lower.starts_with("claude") {
            return (Self::Anthropic, model.to_string());
        }

        if lower.starts_with("gemini") {
            return (Self::Gemini, model.to_string());
        }

        if lower.starts_with("kimi") {
            return (Self::Kimi, model.to_string());
        }

        if lower.starts_with("deepseek") {
            return (Self::DeepSeek, model.to_string());
        }

        if lower.starts_with("grok") {
            return (Self::XAi, model.to_string());
        }

        if lower.starts_with("mistral")
            || lower.starts_with("ministral")
            || lower.starts_with("codestral")
        {
            return (Self::Mistral, model.to_string());
        }

        if lower.starts_with("command") {
            return (Self::Cohere, model.to_string());
        }

        (Self::OpenAi, model.to_string())
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value.to_ascii_lowercase().as_str() {
            "openai" => Some(Self::OpenAi),
            "anthropic" => Some(Self::Anthropic),
            "gemini" => Some(Self::Gemini),
            "kimi" => Some(Self::Kimi),
            "openrouter" => Some(Self::OpenRouter),
            "vercel" => Some(Self::VercelAiGateway),
            "vercel-ai-gateway" => Some(Self::VercelAiGateway),
            "groq" => Some(Self::Groq),
            "deepseek" => Some(Self::DeepSeek),
            "xai" => Some(Self::XAi),
            "mistral" => Some(Self::Mistral),
            "cohere" => Some(Self::Cohere),
            "azure" => Some(Self::AzureOpenAi),
            "azure-openai" => Some(Self::AzureOpenAi),
            "bedrock" => Some(Self::AwsBedrock),
            "aws-bedrock" => Some(Self::AwsBedrock),
            "vertex" => Some(Self::VertexAi),
            "vertex-ai" => Some(Self::VertexAi),
            _ => None,
        }
    }
}

#[derive(Clone)]
pub struct ProviderRegistry {
    openai: Arc<dyn ProviderSdk>,
    anthropic: Arc<dyn ProviderSdk>,
    gemini: Arc<dyn ProviderSdk>,
    kimi: Arc<dyn ProviderSdk>,
    openrouter: Arc<dyn ProviderSdk>,
    vercel_ai_gateway: Arc<dyn ProviderSdk>,
    groq: Arc<dyn ProviderSdk>,
    deepseek: Arc<dyn ProviderSdk>,
    xai: Arc<dyn ProviderSdk>,
    mistral: Arc<dyn ProviderSdk>,
    cohere: Arc<dyn ProviderSdk>,
    azure_openai: Arc<dyn ProviderSdk>,
    aws_bedrock: Arc<dyn ProviderSdk>,
    vertex_ai: Arc<dyn ProviderSdk>,
}

impl ProviderRegistry {
    pub fn new(
        openai: Arc<dyn ProviderSdk>,
        anthropic: Arc<dyn ProviderSdk>,
        gemini: Arc<dyn ProviderSdk>,
        kimi: Arc<dyn ProviderSdk>,
        openrouter: Arc<dyn ProviderSdk>,
        vercel_ai_gateway: Arc<dyn ProviderSdk>,
        groq: Arc<dyn ProviderSdk>,
        deepseek: Arc<dyn ProviderSdk>,
        xai: Arc<dyn ProviderSdk>,
        mistral: Arc<dyn ProviderSdk>,
        cohere: Arc<dyn ProviderSdk>,
        azure_openai: Arc<dyn ProviderSdk>,
        aws_bedrock: Arc<dyn ProviderSdk>,
        vertex_ai: Arc<dyn ProviderSdk>,
    ) -> Self {
        Self {
            openai,
            anthropic,
            gemini,
            kimi,
            openrouter,
            vercel_ai_gateway,
            groq,
            deepseek,
            xai,
            mistral,
            cohere,
            azure_openai,
            aws_bedrock,
            vertex_ai,
        }
    }

    pub fn provider(&self, kind: ProviderKind) -> Arc<dyn ProviderSdk> {
        match kind {
            ProviderKind::OpenAi => Arc::clone(&self.openai),
            ProviderKind::Anthropic => Arc::clone(&self.anthropic),
            ProviderKind::Gemini => Arc::clone(&self.gemini),
            ProviderKind::Kimi => Arc::clone(&self.kimi),
            ProviderKind::OpenRouter => Arc::clone(&self.openrouter),
            ProviderKind::VercelAiGateway => Arc::clone(&self.vercel_ai_gateway),
            ProviderKind::Groq => Arc::clone(&self.groq),
            ProviderKind::DeepSeek => Arc::clone(&self.deepseek),
            ProviderKind::XAi => Arc::clone(&self.xai),
            ProviderKind::Mistral => Arc::clone(&self.mistral),
            ProviderKind::Cohere => Arc::clone(&self.cohere),
            ProviderKind::AzureOpenAi => Arc::clone(&self.azure_openai),
            ProviderKind::AwsBedrock => Arc::clone(&self.aws_bedrock),
            ProviderKind::VertexAi => Arc::clone(&self.vertex_ai),
        }
    }

    pub fn all(&self) -> Vec<(ProviderKind, Arc<dyn ProviderSdk>)> {
        vec![
            (ProviderKind::OpenAi, Arc::clone(&self.openai)),
            (ProviderKind::Anthropic, Arc::clone(&self.anthropic)),
            (ProviderKind::Gemini, Arc::clone(&self.gemini)),
            (ProviderKind::Kimi, Arc::clone(&self.kimi)),
            (ProviderKind::OpenRouter, Arc::clone(&self.openrouter)),
            (
                ProviderKind::VercelAiGateway,
                Arc::clone(&self.vercel_ai_gateway),
            ),
            (ProviderKind::Groq, Arc::clone(&self.groq)),
            (ProviderKind::DeepSeek, Arc::clone(&self.deepseek)),
            (ProviderKind::XAi, Arc::clone(&self.xai)),
            (ProviderKind::Mistral, Arc::clone(&self.mistral)),
            (ProviderKind::Cohere, Arc::clone(&self.cohere)),
            (ProviderKind::AzureOpenAi, Arc::clone(&self.azure_openai)),
            (ProviderKind::AwsBedrock, Arc::clone(&self.aws_bedrock)),
            (ProviderKind::VertexAi, Arc::clone(&self.vertex_ai)),
        ]
    }
}
