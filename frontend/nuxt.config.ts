import tailwindcss from "@tailwindcss/vite";

export default defineNuxtConfig({
  compatibilityDate: "2026-03-16",
  ssr: false,
  devtools: { enabled: true },
  css: ["~/assets/css/tailwind.css"],
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
