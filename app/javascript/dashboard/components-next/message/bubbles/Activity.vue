<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { t } = useI18n();
const { content, createdAt, contentAttributes } = useMessageContext();

const readableTime = computed(() =>
  messageTimestamp(createdAt.value, 'LLL d, h:mm a')
);

const navigationLabel = computed(() =>
  t('CONVERSATION.VISITOR_NAVIGATED_PREFIX')
);

const normalizedContent = computed(() =>
  content.value ? content.value.replace(/<[^>]*>/g, '').trim() : ''
);

const fallbackNavigationPath = computed(() => {
  const label = navigationLabel.value;
  const text = normalizedContent.value;
  if (!label || !text) {
    return '';
  }

  if (!text.startsWith(label)) {
    return '';
  }

  return text.slice(label.length).trim();
});

const navigationPath = computed(() =>
  contentAttributes.value?.path || fallbackNavigationPath.value
);

const isVisitorNavigation = computed(() =>
  contentAttributes.value?.activityIdentifier === 'visitor_navigated' ||
  Boolean(navigationPath.value)
);

const navigationHref = computed(() => {
  if (!navigationPath.value) {
    return '#';
  }

  const baseUrl = 'https://www.versaciboosts.com'.replace(/\/$/, '');
  const formattedPath = navigationPath.value.startsWith('/')
    ? navigationPath.value
    : `/${navigationPath.value}`;

  return `${baseUrl}${formattedPath}`;
});

const bubbleClass = computed(() =>
  isVisitorNavigation.value
    ? '!bg-transparent !px-0 !py-0 w-full !rounded-none'
    : 'px-3 py-1 !rounded-xl flex min-w-0 items-center gap-2'
);

</script>

<template>
  <BaseBubble
    v-tooltip.top="readableTime"
    :class="bubbleClass"
    data-bubble-name="activity"
  >
    <template v-if="isVisitorNavigation">
      <div class="flex w-full items-center gap-3 px-3 py-2">
        <span class="flex-1 h-px bg-n-alpha-4" />
        <div
          class="flex flex-wrap items-center justify-center gap-2 text-xs text-n-slate-11 text-center max-w-full"
        >
          <span>{{ navigationLabel }}</span>
          <a
            :href="navigationHref"
            target="_blank"
            rel="noopener noreferrer"
            class="font-medium text-n-slate-12 break-all hover:text-n-iris-11 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-7 rounded-sm"
            :title="navigationPath"
          >
            {{ navigationPath }}
          </a>
        </div>
        <span class="flex-1 h-px bg-n-alpha-4" />
      </div>
    </template>
    <span v-else v-dompurify-html="content" :title="content" />
  </BaseBubble>
</template>
