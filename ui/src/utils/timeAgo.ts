import { get } from 'svelte/store';
import { Locale, LOCALE_KEY } from '@store/stores';

// ox_lib locale key -> BCP 47 tag, so Intl gives correct month names and date
// punctuation per language instead of us hand-translating twelve month names
// per locale file.
const INTL_LOCALE: Record<string, string> = {
  en: 'en-US',
  de: 'de-DE',
  es: 'es-ES',
  fr: 'fr-FR',
  nl: 'nl-NL',
  'pt-br': 'pt-BR',
  tr: 'tr-TR',
  cs: 'cs-CZ',
};

function intlLocale() {
  return INTL_LOCALE[get(LOCALE_KEY)] || 'en-US';
}

function t(key: string, fallback: string, n?: number | string) {
  const value = (get(Locale) as any)?.[key] ?? fallback;
  return n === undefined ? value : value.replace('%s', String(n));
}

function getFormattedDate(date, prefomattedDate: string | false = false, hideYear = false) {
  const day = date.getDate();
  const month = date.toLocaleString(intlLocale(), { month: 'long' });
  const year = date.getFullYear();
  const hours = date.getHours();
  let minutes: number | string = date.getMinutes();

  if (minutes < 10) {
      minutes = `0${minutes}`;
  }

  const at = t('time_at', 'at');

  if (prefomattedDate) {
      return `${prefomattedDate} ${at} ${hours}:${minutes}`;
  }

  if (hideYear) {
      return `${day}. ${month} ${at} ${hours}:${minutes}`;
  }

      return `${day}. ${month} ${year}. ${at} ${hours}:${minutes}`;
  }


export function timeAgo(dateParam) {
  if (!dateParam) {
  return t('time_unknown', 'Unknown');
  }

  let date;
  try {
  date =  typeof dateParam === 'object' ? dateParam : new Date(dateParam);
  } catch (e) {
  return t('time_invalid_date', 'Invalid date');
  }

  if (isNaN(date)) {
  return t('time_invalid_date', 'Invalid date');
  }
  const DAY_IN_MS = 86400000;
  const today = new Date();
  const yesterday = new Date(today - DAY_IN_MS);
  const seconds = Math.round((today - date) / 1000);
  const minutes = Math.round(seconds / 60);
  const isToday = today.toDateString() === date.toDateString();
  const isYesterday = yesterday.toDateString() === date.toDateString();
  const isThisYear = today.getFullYear() === date.getFullYear();

  if (seconds < 5) {
      return t('time_just_now', 'Just now');
  } else if (seconds < 60) {
      return t('time_seconds_ago', '%s seconds ago', seconds);
  } else if (seconds < 90) {
      return t('time_minute_ago', 'A minute ago');
  } else if (minutes < 60) {
      return t('time_minutes_ago', '%s minutes ago', minutes);
  } else if (isToday) {
      return getFormattedDate(date, t('time_today', 'Today'));
  } else if (isYesterday) {
      return getFormattedDate(date, t('time_yesterday', 'Yesterday'));
  } else if (isThisYear) {
      return getFormattedDate(date, false, true);
  }

  return getFormattedDate(date);
}
