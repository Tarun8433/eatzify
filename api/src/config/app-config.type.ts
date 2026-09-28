export type AppConfig = {
  nodeEnv: string;
  name: string;
  workingDirectory: string;
  frontendDomain?: string;
  backendDomain: string;
  corsOrigins: string[];
  port: number;
  apiPrefix: string;
  /// Salt for the one-trial-per-number check (docs/11 §6). Never the number itself, and never a
  /// secret that rotates — rotating it would hand everybody a second trial.
  trialPepper: string;
  fallbackLanguage: string;
  headerLanguage: string;
};
