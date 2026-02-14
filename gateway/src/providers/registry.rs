use std::sync::Arc;

use crate::sdk::ProviderSdk;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProviderKind {
    OpenAi,
    Anthropic,
    Gemini,
    Kimi,
}

impl ProviderKind {
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

        (Self::OpenAi, model.to_string())
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value.to_ascii_lowercase().as_str() {
            "openai" => Some(Self::OpenAi),
            "anthropic" => Some(Self::Anthropic),
            "gemini" => Some(Self::Gemini),
            "kimi" => Some(Self::Kimi),
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
}

impl ProviderRegistry {
    pub fn new(
        openai: Arc<dyn ProviderSdk>,
        anthropic: Arc<dyn ProviderSdk>,
        gemini: Arc<dyn ProviderSdk>,
        kimi: Arc<dyn ProviderSdk>,
    ) -> Self {
        Self {
            openai,
            anthropic,
            gemini,
            kimi,
        }
    }

    pub fn provider(&self, kind: ProviderKind) -> Arc<dyn ProviderSdk> {
        match kind {
            ProviderKind::OpenAi => Arc::clone(&self.openai),
            ProviderKind::Anthropic => Arc::clone(&self.anthropic),
            ProviderKind::Gemini => Arc::clone(&self.gemini),
            ProviderKind::Kimi => Arc::clone(&self.kimi),
        }
    }

    pub fn all(&self) -> Vec<(ProviderKind, Arc<dyn ProviderSdk>)> {
        vec![
            (ProviderKind::OpenAi, Arc::clone(&self.openai)),
            (ProviderKind::Anthropic, Arc::clone(&self.anthropic)),
            (ProviderKind::Gemini, Arc::clone(&self.gemini)),
            (ProviderKind::Kimi, Arc::clone(&self.kimi)),
        ]
    }
}
