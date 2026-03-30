/**
 * Router configuration.
 *
 * Auth guard uses Firebase auth state.
 */

import { createRouter, createWebHistory } from 'vue-router'
import { auth } from '@/services/firebase'
import { onAuthStateChanged } from 'firebase/auth'

function waitForAuth(): Promise<void> {
  return new Promise((resolve) => {
    if (auth.currentUser !== undefined) {
      const unsubscribe = onAuthStateChanged(auth, () => {
        unsubscribe()
        resolve()
      })
    } else {
      resolve()
    }
  })
}

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/app/home' },
    { path: '/login', component: () => import('@/pages/login.vue'), meta: { guestOnly: true } },
    { path: '/signup', redirect: '/login' },
    {
      path: '/app',
      component: () => import('@/layouts/AppLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        { path: 'home', component: () => import('@/pages/app/home.vue') },
        { path: 'reflect', component: () => import('@/pages/app/reflect/index.vue') },
        { path: 'reflect/chat/:id', component: () => import('@/pages/app/reflect/chat.vue') },
        { path: 'reflect/journal/new', component: () => import('@/pages/app/reflect/journal-new.vue') },
        { path: 'reflect/journal/:id', component: () => import('@/pages/app/reflect/journal-edit.vue') },
        { path: 'reflect/voice/:id', component: () => import('@/pages/app/reflect/voice-detail.vue') },
        { path: 'journey', component: () => import('@/pages/app/journey.vue') },
        { path: 'journey/goals/:id', component: () => import('@/pages/app/goal-detail.vue') },
        { path: 'journey/insights', component: () => import('@/pages/app/journey-insights.vue') },
        { path: 'about', component: () => import('@/pages/app/about.vue') },
        { path: '', redirect: 'home' },
      ],
    },
  ],
})

router.beforeEach(async (to) => {
  await waitForAuth()
  const isSignedIn = !!auth.currentUser
  if (to.meta.guestOnly && isSignedIn) return '/app/home'
  if (to.meta.requiresAuth && !isSignedIn) return '/login'
})

export default router
