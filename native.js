import {Capacitor} from '@capacitor/core';
import {App} from '@capacitor/app';
import {Clipboard} from '@capacitor/clipboard';
export const isNative=Capacitor.isNativePlatform();
export async function copyText(value){if(isNative)await Clipboard.write({string:value});else await navigator.clipboard.writeText(value);}
export function watchAppState(callback){if(!isNative)return;document.documentElement.classList.add('native-app');App.addListener('appStateChange',({isActive})=>callback(isActive)).catch(console.error);}
