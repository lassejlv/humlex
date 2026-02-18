use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub openai_base_url: String,
    pub anthropic_base_url: String,
    pub gemini_base_url: String,
    pub kimi_base_url: String,
    pub openrouter_base_url: String,
    pub vercel_ai_gateway_base_url: String,
    pub groq_base_url: String,
    pub deepseek_base_url: String,
    pub xai_base_url: String,
    pub mistral_base_url: String,
    pub cohere_base_url: String,
    pub azure_openai_base_url: String,
    pub aws_bedrock_base_url: String,
    pub vertex_ai_base_url: String,
    pub gateway_api_keys: Vec<String>,
    pub openai_api_key: Option<String>,
    pub anthropic_api_key: Option<String>,
    pub gemini_api_key: Option<String>,
    pub kimi_api_key: Option<String>,
    pub openrouter_api_key: Option<String>,
    pub vercel_ai_gateway_api_key: Option<String>,
    pub groq_api_key: Option<String>,
    pub deepseek_api_key: Option<String>,
    pub xai_api_key: Option<String>,
    pub mistral_api_key: Option<String>,
    pub cohere_api_key: Option<String>,
    pub azure_openai_api_key: Option<String>,
    pub aws_bedrock_api_key: Option<String>,
    pub vertex_ai_api_key: Option<String>,
    pub upstream_max_retries: u32,
    pub upstream_retry_base_delay_ms: u64,
    pub request_timeout_secs: u64,
}

impl Config {
    pub fn from_env() -> Self {
        let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
        let port = env::var("PORT")
            .ok()
            .and_then(|value| value.parse::<u16>().ok())
            .unwrap_or(3000);

        let openai_base_url = env::var("OPENAI_BASE_URL")
            .unwrap_or_else(|_| "https://api.openai.com".to_string())
            .trim_end_matches('/')
            .to_string();

        let anthropic_base_url = env::var("ANTHROPIC_BASE_URL")
            .unwrap_or_else(|_| "https://api.anthropic.com".to_string())
            .trim_end_matches('/')
            .to_string();

        let gemini_base_url = env::var("GEMINI_BASE_URL")
            .unwrap_or_else(|_| {
                "https://generativelanguage.googleapis.com/v1beta/openai".to_string()
            })
            .trim_end_matches('/')
            .to_string();

        let kimi_base_url = env::var("KIMI_BASE_URL")
            .unwrap_or_else(|_| "https://api.kimi.com/coding/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let openrouter_base_url = env::var("OPENROUTER_BASE_URL")
            .unwrap_or_else(|_| "https://openrouter.ai/api/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let vercel_ai_gateway_base_url = env::var("VERCEL_AI_GATEWAY_BASE_URL")
            .unwrap_or_else(|_| "https://ai-gateway.vercel.sh/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let groq_base_url = env::var("GROQ_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com/openai/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let deepseek_base_url = env::var("DEEPSEEK_BASE_URL")
            .unwrap_or_else(|_| "https://api.deepseek.com/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let xai_base_url = env::var("XAI_BASE_URL")
            .unwrap_or_else(|_| "https://api.x.ai/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let mistral_base_url = env::var("MISTRAL_BASE_URL")
            .unwrap_or_else(|_| "https://api.mistral.ai/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let cohere_base_url = env::var("COHERE_BASE_URL")
            .unwrap_or_else(|_| "https://api.cohere.com/compatibility/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let azure_openai_base_url = env::var("AZURE_OPENAI_BASE_URL")
            .unwrap_or_else(|_| "https://example-resource.openai.azure.com/openai/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let aws_bedrock_base_url = env::var("AWS_BEDROCK_BASE_URL")
            .unwrap_or_else(|_| {
                "https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1".to_string()
            })
            .trim_end_matches('/')
            .to_string();

        let vertex_ai_base_url = env::var("VERTEX_AI_BASE_URL")
            .unwrap_or_else(|_| {
                "https://us-central1-aiplatform.googleapis.com/v1/projects/PROJECT/locations/us-central1/endpoints/openapi".to_string()
            })
            .trim_end_matches('/')
            .to_string();

        let request_timeout_secs = env::var("REQUEST_TIMEOUT_SECS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(120);

        let gateway_api_keys = env::var("GATEWAY_API_KEYS")
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
            .collect::<Vec<_>>();

        let openai_api_key = env::var("OPENAI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let anthropic_api_key = env::var("ANTHROPIC_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let gemini_api_key = env::var("GEMINI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let kimi_api_key = env::var("KIMI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let openrouter_api_key = env::var("OPENROUTER_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let vercel_ai_gateway_api_key = env::var("VERCEL_AI_GATEWAY_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let groq_api_key = env::var("GROQ_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let deepseek_api_key = env::var("DEEPSEEK_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let xai_api_key = env::var("XAI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let mistral_api_key = env::var("MISTRAL_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let cohere_api_key = env::var("COHERE_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let azure_openai_api_key = env::var("AZURE_OPENAI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let aws_bedrock_api_key = env::var("AWS_BEDROCK_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let vertex_ai_api_key = env::var("VERTEX_AI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let upstream_max_retries = env::var("UPSTREAM_MAX_RETRIES")
            .ok()
            .and_then(|value| value.parse::<u32>().ok())
            .unwrap_or(2);

        let upstream_retry_base_delay_ms = env::var("UPSTREAM_RETRY_BASE_DELAY_MS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(150);

        Self {
            host,
            port,
            openai_base_url,
            anthropic_base_url,
            gemini_base_url,
            kimi_base_url,
            openrouter_base_url,
            vercel_ai_gateway_base_url,
            groq_base_url,
            deepseek_base_url,
            xai_base_url,
            mistral_base_url,
            cohere_base_url,
            azure_openai_base_url,
            aws_bedrock_base_url,
            vertex_ai_base_url,
            gateway_api_keys,
            openai_api_key,
            anthropic_api_key,
            gemini_api_key,
            kimi_api_key,
            openrouter_api_key,
            vercel_ai_gateway_api_key,
            groq_api_key,
            deepseek_api_key,
            xai_api_key,
            mistral_api_key,
            cohere_api_key,
            azure_openai_api_key,
            aws_bedrock_api_key,
            vertex_ai_api_key,
            upstream_max_retries,
            upstream_retry_base_delay_ms,
            request_timeout_secs,
        }
    }

    pub fn bind_addr(&self) -> String {
        format!("{}:{}", self.host, self.port)
    }
}
