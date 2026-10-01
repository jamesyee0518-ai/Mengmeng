/// Shared endpoint for chat, speech recognition and health checks.
const defaultGatewayBaseUrl = String.fromEnvironment(
  'AI_GATEWAY_BASE_URL',
  defaultValue: 'https://aipipeline.hiqer.top/mengmeng/gw',
);

// Public proxy checks include upstream STT/LLM probes and can exceed 2 seconds.
const gatewayHealthTimeout = Duration(seconds: 12);
