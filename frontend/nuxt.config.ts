import tailwindcss from "@tailwindcss/vite";

export default defineNuxtConfig({
  compatibilityDate: "2026-03-16",
  modules: ["@clerk/nuxt", "@pinia/nuxt"],
  css: ["~/assets/css/tailwind.css"],
  runtimeConfig: {
    public: {
      apiBaseUrl: process.env.NUXT_PUBLIC_API_BASE_URL || "http://localhost:8080",
      clerkPublishableKey: process.env.NUXT_PUBLIC_CLERK_PUBLISHABLE_KEY || "",
    },
  },
  clerk: {
    publishableKey: process.env.NUXT_PUBLIC_CLERK_PUBLISHABLE_KEY,
  },
  ssr: false,
  devtools: { enabled: true },
  vite: {
    plugins: [tailwindcss()],
  },
  app: {
    head: {
      title: "ShantiSangha",
      meta: [
        {
          name: "description",
          content:
            "A wellness companion for emotional support, reflection, and everyday mental well-being.",
        },
        { name: "theme-color", content: "#f6efe5" },
      ],
    },
  },
});
