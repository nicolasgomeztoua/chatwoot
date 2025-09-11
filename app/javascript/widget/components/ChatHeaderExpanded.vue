<script setup>
import HeaderActions from './HeaderActions.vue';
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { getActiveCountryCode } from 'shared/components/PhoneInput/helper';
import { getCountryFlag } from 'dashboard/helper/flag';
import countries from 'shared/constants/countries';

const props = defineProps({
  avatarUrl: {
    type: String,
    default: '',
  },
  introHeading: {
    type: String,
    default: '',
  },
  introBody: {
    type: String,
    default: '',
  },
  showPopoutButton: {
    type: Boolean,
    default: false,
  },
});

const { formatMessage } = useMessageFormatter();

const containerClasses = computed(() => [
  props.avatarUrl ? 'justify-between' : 'justify-end',
]);

const store = useStore();
const currentUser = computed(
  () => store.getters['contacts/getCurrentUser'] || {}
);
const countryCode = computed(() => {
  const codeFromUser = currentUser.value?.additional_attributes?.country_code;
  return codeFromUser || getActiveCountryCode() || '';
});
const countryFlag = computed(() =>
  countryCode.value ? getCountryFlag(countryCode.value) : ''
);
const countryName = computed(() => {
  const code = countryCode.value ? countryCode.value.toUpperCase() : '';
  const match = countries.find(c => c.id === code);
  return match ? match.name : '';
});
</script>

<template>
  <header
    class="header-expanded pt-6 pb-4 px-5 relative box-border w-full bg-transparent"
  >
    <div class="flex items-start" :class="containerClasses">
      <img
        v-if="avatarUrl"
        class="h-12 rounded-full"
        :src="avatarUrl"
        alt="Avatar"
      />
      <HeaderActions
        :show-popout-button="showPopoutButton"
        :show-end-conversation-button="false"
      />
    </div>
    <div class="mt-4 mb-1.5 flex items-center gap-2">
      <h2
        v-dompurify-html="introHeading"
        class="text-2xl font-medium text-n-slate-12 line-clamp-4"
      />
      <span v-if="countryFlag" :title="countryName" class="text-base"
        >{{ countryFlag }}</span
      >
    </div>
    <p
      v-dompurify-html="formatMessage(introBody)"
      class="text-lg leading-normal text-n-slate-11 [&_a]:underline line-clamp-6"
    />
  </header>
</template>
