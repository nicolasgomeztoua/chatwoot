import { API } from 'widget/helpers/axios';
import { buildSearchParamsWithLocale } from '../helpers/urlParamsHelper';

export const generateEventParams = () => {
  const locationHref =
    typeof window !== 'undefined' && window.location ? window.location.href : '';
  const docReferrer =
    typeof document !== 'undefined' && document.referrer ? document.referrer : '';

  return {
    initiated_at: {
      timestamp: new Date().toString(),
    },
    // Prefer SDK-provided referrerURL, then document.referrer, then current location
    referer: window.referrerURL || docReferrer || locationHref || '',
  };
};

export default {
  create(name) {
    const search = buildSearchParamsWithLocale(window.location.search);
    return API.post(`/api/v1/widget/events${search}`, {
      name,
      event_info: generateEventParams(),
    });
  },
};
