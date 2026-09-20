// No ad network is connected. No ad requests, tracking, or SDK initialization.
export const adSettings={enabled:false,minimumIntervalMs:180000};
// Replace null with a provider adapter after its account, consent and SDK are set up.
// Contract: canRequestAds(): boolean; isReady(): boolean;
// show({placement}): Promise<boolean> (true after dismissal, false on failure).
export const adProvider=null;
