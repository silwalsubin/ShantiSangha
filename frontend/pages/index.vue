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
  <main class="page-shell">
    <section class="hero">
      <div class="hero-copy">
        <p class="eyebrow">ShantiSangha</p>
        <h1>A calmer place to return to when life feels emotionally heavy.</h1>
        <p class="hero-text">
          ShantiSangha is a wellness companion for emotional support,
          reflection, and everyday mental well-being. It helps people process
          what they are feeling, build self-awareness, and find a private,
          steady place for emotional grounding.
        </p>
        <div class="hero-actions">
          <a href="#features" class="primary-action">Explore the experience</a>
          <a href="#vision" class="secondary-action">Read the vision</a>
        </div>
      </div>

      <div class="hero-card">
        <span class="card-badge">Wellness-first</span>
        <div class="reflection-card">
          <p class="reflection-label">Today's check-in</p>
          <p class="reflection-question">
            What has been sitting quietly in your mind that needs a little more
            compassion?
          </p>
          <div class="pulse-row">
            <span />
            <span />
            <span />
          </div>
        </div>
        <div class="trust-panel">
          <p>
            Made for reflection, mood support, journaling, and steady emotional
            care.
          </p>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="intro-card">
        <p class="section-kicker">Why it matters</p>
        <h2>Many people need support before they ever ask for help.</h2>
        <p>
          ShantiSangha exists for the in-between moments: when someone feels
          overwhelmed, isolated, anxious, or mentally tired and wants a grounded
          place to reflect without pressure or judgment.
        </p>
      </div>

      <div class="principles-card">
        <p class="section-kicker">Product principles</p>
        <ul>
          <li v-for="principle in principles" :key="principle">
            {{ principle }}
          </li>
        </ul>
      </div>
    </section>

    <section id="features" class="features-section">
      <div class="section-heading">
        <p class="section-kicker">Core features</p>
        <h2>Built around the ways people actually seek emotional support.</h2>
      </div>

      <div class="feature-grid">
        <article v-for="feature in features" :key="feature.title" class="feature-card">
          <h3>{{ feature.title }}</h3>
          <p>{{ feature.description }}</p>
        </article>
      </div>
    </section>

    <section class="journey-section">
      <div class="section-heading">
        <p class="section-kicker">A day with ShantiSangha</p>
        <h2>Small moments of support that add up to real emotional steadiness.</h2>
      </div>

      <div class="journey-grid">
        <article v-for="item in journey" :key="item.label" class="journey-card">
          <p class="journey-label">{{ item.label }}</p>
          <p>{{ item.text }}</p>
        </article>
      </div>
    </section>

    <section id="vision" class="vision-section">
      <div class="vision-panel">
        <p class="section-kicker">Vision</p>
        <h2>
          A trusted wellness companion for reflection, emotional support, and
          everyday well-being.
        </h2>
        <p>
          The long-term goal is to help people feel less alone, more
          self-aware, and more supported in their daily lives with a product
          that feels calm, human, and worth returning to.
        </p>
      </div>

      <div class="cta-panel">
        <p class="section-kicker">Next step</p>
        <h3>Ready for the product buildout.</h3>
        <p>
          This frontend establishes the brand direction, product framing, and
          experience foundation for the app we will keep expanding.
        </p>
      </div>
    </section>
  </main>
</template>
