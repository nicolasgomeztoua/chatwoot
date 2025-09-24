import { API } from 'widget/helpers/axios';
import { buildSearchParamsWithLocale } from '../helpers/urlParamsHelper';

export const generateEventParams = () => {
  const locationHref =
    typeof window !== 'undefined' && window.location ? window.location.href : '';

  return {
    initiated_at: {
      timestamp: new Date().toString(),
    },
    referer: window.referrerURL || locationHref || '',
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
