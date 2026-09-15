declare const _default: () => {
    port: number;
    instanceId: string;
    appName: any;
    databaseUrl: string;
    googleClientId: any;
    youtubeApiKey: string;
    youtubeClientId: any;
    youtubeClientSecret: any;
    youtubeRefreshToken: any;
    shorts: {
        enabled: any;
        customChannelId: any;
        dailyQuotaUnits: any;
        uploadCostUnits: any;
        maxDurationSeconds: any;
        defaultPrivacyStatus: any;
        selfDeclaredMadeForKids: any;
    };
    geminiApiKey: string;
    transcriptionModel: string;
    transcriptionEnabled: boolean;
    storage: {
        endpoint: string;
        region: string;
        bucket: string;
        accessKey: string;
        secretKey: string;
        publicUrl: string;
    };
    embedding: {
        provider: string;
        serviceUrl: string;
        authToken: string;
        model: string;
        dim: number;
        version: number;
        timeoutMs: number;
        enabled: boolean;
    };
    contentSearch: {
        enabled: boolean;
        maxChunks: number;
    };
    internalJobSecret: string;
    githubToken: string;
    githubRepo: string;
    adminEmails: string[];
    instanceConfig: any;
    seedChannels: any[];
};
export default _default;
