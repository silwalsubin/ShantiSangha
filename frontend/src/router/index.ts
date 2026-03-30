/**
 * Router configuration.
 *
 * Structure:
 * - /login, /signup  — guest-only auth pages (Clerk)
 * - /app/*           — authenticated pages wrapped in AppLayout
 *   - home           — "What needs your attention today?" (tasks/goals)
 *   - reflect        — conversations, journals, voice notes
 *   - journey        — progress tracking, streaks, milestones
 *
 * All routes are lazy-loaded. Auth guard uses Clerk's useAuth().
 */

import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from '@clerk/vue'
import { watch } from 'vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/app/home' },
    { path: '/login', component: () => import('@/pages/login.vue'), meta: { guestOnly: true } },
    { path: '/signup', component: () => import('@/pages/signup.vue'), meta: { guestOnly: true } },
    {
      path: '/app',
      component: () => import('@/layouts/AppLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        // Home — daily task check-ins
        { path: 'home', component: () => import('@/pages/app/home.vue') },

        // Reflect — conversations, journals, voice
        { path: 'reflect', component: () => import('@/pages/app/reflect/index.vue') },
        { path: 'reflect/chat/:id', component: () => import('@/pages/app/reflect/chat.vue') },
        { path: 'reflect/journal/new', component: () => import('@/pages/app/reflect/journal-new.vue') },
        { path: 'reflect/journal/:id', component: () => import('@/pages/app/reflect/journal-edit.vue') },
        { path: 'reflect/voice/:id', component: () => import('@/pages/app/reflect/voice-detail.vue') },

        // Journey — goals, streaks, insights
        { path: 'journey', component: () => import('@/pages/app/journey.vue') },
        { path: 'journey/goals/:id', component: () => import('@/pages/app/goal-detail.vue') },
        { path: 'journey/insights', component: () => import('@/pages/app/journey-insights.vue') },

        // About
        { path: 'about', component: () => import('@/pages/app/about.vue') },

        // Catch-all
        { path: '', redirect: 'home' },
      ],
    },
  ],
})

router.beforeEach(async (to) => {
  const { isSignedIn, isLoaded } = useAuth()
  if (!isLoaded.value) {
    await new Promise<void>((resolve) => {
      const unwatch = watch(isLoaded, (val) => {
        if (val) { unwatch(); resolve() }
      })
    })
  }
  if (to.meta.guestOnly && isSignedIn.value) return '/app/home'
  if (to.meta.requiresAuth && !isSignedIn.value) return '/login'
})

export default router
