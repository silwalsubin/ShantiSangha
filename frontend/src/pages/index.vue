<script setup lang="ts">
const features = [
  {
    title: "Emotional Support Conversations",
    description:
      "Calm, reflective conversations that help users process difficult moments and feel less alone.",
  },
  {
    title: "Guided Reflection",
    description:
      "Thoughtful prompts that turn overwhelm into clarity and offer a gentle place to begin.",
  },
  {
    title: "Journaling and Voice Notes",
    description:
      "Write or speak thoughts out loud when emotions feel tangled and expression needs more space.",
  },
  {
    title: "Mood Check-Ins",
    description:
      "Simple recurring check-ins that help users notice patterns and build emotional awareness over time.",
  },
  {
    title: "Coping Support",
    description:
      "Grounding exercises for stress, emotional fatigue, and mentally heavy moments that need a reset.",
  },
  {
    title: "Summaries and Saved Insights",
    description:
      "Helpful takeaways that preserve what mattered most so users can return to their own progress.",
  },
];

const principles = [
  "Supportive, not clinical",
  "Private, calm, and non-judgmental",
  "Designed for everyday emotional well-being",
  "Gentle enough to return to, structured enough to help",
];

const journey = [
  {
    label: "Morning",
    text: "A quick mood check-in and a grounding reflection create a steadier start before the day begins.",
  },
  {
    label: "Midday",
    text: "A hard moment becomes a short support conversation and a coping exercise instead of spiraling.",
  },
  {
    label: "Evening",
    text: "The day winds down with a voice journal, a summary, and one saved insight to carry forward.",
  },
];
</script>

<template>
  <main
    class="min-h-screen bg-[radial-gradient(circle_at_top_left,rgba(201,146,98,0.28),transparent_28%),radial-gradient(circle_at_top_right,rgba(126,146,120,0.22),transparent_26%),linear-gradient(180deg,#f9f2e8_0%,#f6efe5_48%,#f2e7da_100%)] px-2 py-4 text-[#2b221a] sm:px-4 sm:py-8"
  >
    <div class="mx-auto flex w-full max-w-[1180px] flex-col gap-6">
      <section class="grid gap-6 lg:grid-cols-[1.2fr_0.8fr]">
        <div
          class="rounded-[2rem] border border-[rgba(101,76,52,0.16)] bg-[rgba(255,250,243,0.72)] px-5 py-6 shadow-[0_24px_80px_rgba(82,54,29,0.12)] backdrop-blur-[18px] sm:px-8 sm:py-12 lg:rounded-[2rem_5rem_2rem_2rem]"
        >
          <p
            class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
          >
            ShantiSangha
          </p>
          <h1
            class="mt-3 max-w-[9ch] font-serif text-[3.4rem] leading-[0.96] sm:max-w-[11ch] sm:text-[5.2rem]"
          >
            A calmer place to return to when life feels emotionally heavy.
          </h1>
          <p class="mt-5 max-w-[61ch] text-[1.08rem] leading-[1.72] text-[#6c5c4d]">
            ShantiSangha is a wellness companion for emotional support,
            reflection, and everyday mental well-being. It helps people process
            what they are feeling, build self-awareness, and find a private,
            steady place for emotional grounding.
          </p>
          <div class="mt-8 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
            <a
              href="#features"
              class="rounded-full bg-[#2b221a] px-5 py-3 text-center font-bold text-[#fff8f1] transition hover:-translate-y-0.5"
            >
              Explore the experience
            </a>
            <a
              href="#vision"
              class="rounded-full border border-[rgba(101,76,52,0.16)] bg-[rgba(255,248,239,0.92)] px-5 py-3 text-center font-bold text-[#2b221a] transition hover:-translate-y-0.5"
            >
              Read the vision
            </a>
          </div>
        </div>

        <div
          class="flex flex-col gap-4 rounded-[2rem] border border-[rgba(101,76,52,0.16)] bg-[rgba(255,250,243,0.72)] p-5 shadow-[0_24px_80px_rgba(82,54,29,0.12)] backdrop-blur-[18px]"
        >
          <span
            class="inline-flex w-fit rounded-full bg-[rgba(138,91,63,0.08)] px-3 py-2 text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
          >
            Wellness-first
          </span>
          <div
            class="rounded-3xl border border-[rgba(138,91,63,0.1)] bg-[rgba(255,248,239,0.92)] p-6"
          >
            <p
              class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
            >
              Today's check-in
            </p>
            <p class="mt-4 text-[1.28rem] font-semibold leading-[1.45] text-[#2b221a]">
              What has been sitting quietly in your mind that needs a little
              more compassion?
            </p>
            <div class="mt-6 flex gap-2">
              <span
                class="h-3 w-3 animate-pulse rounded-full bg-gradient-to-b from-[#c99262] to-[#8a5b3f]"
              />
              <span
                class="h-3 w-3 animate-pulse rounded-full bg-gradient-to-b from-[#c99262] to-[#8a5b3f] [animation-delay:200ms]"
              />
              <span
                class="h-3 w-3 animate-pulse rounded-full bg-gradient-to-b from-[#c99262] to-[#8a5b3f] [animation-delay:400ms]"
              />
            </div>
          </div>
          <div
            class="rounded-3xl border border-[rgba(138,91,63,0.1)] bg-[rgba(255,248,239,0.92)] px-5 py-4"
          >
            <p class="leading-[1.72] text-[#6c5c4d]">
              Made for reflection, mood support, journaling, and steady emotional
              care.
            </p>
          </div>
        </div>
      </section>

      <section class="grid gap-6 lg:grid-cols-2">
        <div
          class="rounded-[1.75rem] border border-[rgba(101,76,52,0.16)] bg-[rgba(255,250,243,0.72)] p-5 shadow-[0_24px_80px_rgba(82,54,29,0.12)] backdrop-blur-[18px] sm:p-8"
        >
          <p
            class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
          >
            Why it matters
          </p>
          <h2 class="mt-3 max-w-[14ch] font-serif text-[2.2rem] leading-[0.96] sm:text-[3rem]">
            Many people need support before they ever ask for help.
          </h2>
          <p class="mt-4 leading-[1.72] text-[#6c5c4d]">
            ShantiSangha exists for the in-between moments: when someone feels
            overwhelmed, isolated, anxious, or mentally tired and wants a grounded
            place to reflect without pressure or judgment.
          </p>
        </div>

        <div
          class="rounded-[1.75rem] border border-[rgba(101,76,52,0.16)] bg-[rgba(255,250,243,0.72)] p-5 shadow-[0_24px_80px_rgba(82,54,29,0.12)] backdrop-blur-[18px] sm:p-8"
        >
          <p
            class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
          >
            Product principles
          </p>
          <ul class="mt-6 grid gap-3">
            <li
              v-for="principle in principles"
              :key="principle"
              class="rounded-2xl border border-[rgba(138,91,63,0.08)] bg-[rgba(255,248,239,0.86)] px-4 py-4 text-[#2b221a]"
            >
              {{ principle }}
            </li>
          </ul>
        </div>
      </section>

      <section id="features" class="pt-2">
        <div class="mb-5">
          <p
            class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
          >
            Core features
          </p>
          <h2 class="mt-3 max-w-[14ch] font-serif text-[2.2rem] leading-[0.96] sm:text-[3rem]">
            Built around the ways people actually seek emotional support.
          </h2>
        </div>

        <div class="grid gap-4 lg:grid-cols-3">
          <article
            v-for="feature in features"
            :key="feature.title"
            class="rounded-3xl border border-[rgba(101,76,52,0.16)] bg-[rgba(255,250,243,0.72)] p-6 shadow-[0_24px_80px_rgba(82,54,29,0.12)] backdrop-blur-[18px]"
          >
            <h3 class="font-serif text-[1.55rem] leading-[1]">
              {{ feature.title }}
            </h3>
            <p class="mt-4 leading-[1.72] text-[#6c5c4d]">
              {{ feature.description }}
            </p>
          </article>
        </div>
      </section>

      <section class="pt-2">
        <div class="mb-5">
          <p
            class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
          >
            A day with ShantiSangha
          </p>
          <h2 class="mt-3 max-w-[14ch] font-serif text-[2.2rem] leading-[0.96] sm:text-[3rem]">
            Small moments of support that add up to real emotional steadiness.
          </h2>
        </div>

        <div class="grid gap-4 lg:grid-cols-3">
          <article
            v-for="item in journey"
            :key="item.label"
            class="rounded-3xl border border-[rgba(101,76,52,0.16)] bg-[rgba(255,250,243,0.72)] p-6 shadow-[0_24px_80px_rgba(82,54,29,0.12)] backdrop-blur-[18px]"
          >
            <p
              class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
            >
              {{ item.label }}
            </p>
            <p class="mt-4 leading-[1.72] text-[#6c5c4d]">
              {{ item.text }}
            </p>
          </article>
        </div>
      </section>

      <section id="vision" class="grid gap-6 lg:grid-cols-2">
        <div
          class="rounded-[1.75rem] border border-[rgba(101,76,52,0.16)] bg-[rgba(255,250,243,0.72)] p-5 shadow-[0_24px_80px_rgba(82,54,29,0.12)] backdrop-blur-[18px] sm:p-8"
        >
          <p
            class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
          >
            Vision
          </p>
          <h2 class="mt-3 max-w-[14ch] font-serif text-[2.2rem] leading-[0.96] sm:text-[3rem]">
            A trusted wellness companion for reflection, emotional support, and
            everyday well-being.
          </h2>
          <p class="mt-4 leading-[1.72] text-[#6c5c4d]">
            The long-term goal is to help people feel less alone, more
            self-aware, and more supported in their daily lives with a product
            that feels calm, human, and worth returning to.
          </p>
        </div>

        <div
          class="rounded-[1.75rem] border border-[rgba(101,76,52,0.16)] bg-[rgba(255,250,243,0.72)] p-5 shadow-[0_24px_80px_rgba(82,54,29,0.12)] backdrop-blur-[18px] sm:p-8"
        >
          <p
            class="text-[0.74rem] font-bold uppercase tracking-[0.14em] text-[#8a5b3f]"
          >
            Next step
          </p>
          <h3 class="mt-3 font-serif text-[1.7rem] leading-[1] sm:text-[2rem]">
            Ready for the product buildout.
          </h3>
          <p class="mt-4 leading-[1.72] text-[#6c5c4d]">
            This frontend establishes the brand direction, product framing, and
            experience foundation for the app we will keep expanding.
          </p>
        </div>
      </section>
    </div>
  </main>
</template>
