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
        { path: 'home', component: () => import('@/pages/app/home.vue') },
        { path: 'reflect', component: () => import('@/pages/app/reflect/index.vue') },
        { path: 'reflect/chat/:id', component: () => import('@/pages/app/reflect/chat.vue') },
        { path: 'reflect/journal/new', component: () => import('@/pages/app/reflect/journal-new.vue') },
        { path: 'reflect/journal/:id', component: () => import('@/pages/app/reflect/journal-edit.vue') },
        { path: 'reflect/voice/:id', component: () => import('@/pages/app/reflect/voice-detail.vue') },
        { path: 'journey', component: () => import('@/pages/app/journey.vue') },
        { path: 'journey/goals/:id', component: () => import('@/pages/app/goal-detail.vue') },
        { path: 'journey/insights', component: () => import('@/pages/app/journey-insights.vue') },
        // Legacy redirects
        { path: 'dashboard', redirect: '/app/home' },
        { path: 'chat', redirect: '/app/reflect' },
        { path: 'chat/:id', redirect: to => `/app/reflect/chat/${to.params.id}` },
        { path: 'journal', redirect: '/app/reflect' },
        { path: 'journal/new', redirect: '/app/reflect/journal/new' },
        { path: 'journal/:id', redirect: to => `/app/reflect/journal/${to.params.id}` },
        { path: 'mood', redirect: '/app/journey' },
        { path: 'coping', redirect: '/app/home' },
        { path: 'insights', redirect: '/app/journey/insights' },
        { path: 'voice', redirect: '/app/reflect' },
        { path: '', redirect: 'home' }
      ]
    }
  ]
})

router.beforeEach(async (to) => {
  const { isSignedIn, isLoaded } = useAuth()
  if (!isLoaded.value) {
    await new Promise<void>(resolve => {
      const unwatch = watch(isLoaded, (val) => { if (val) { unwatch(); resolve() } })
    })
  }
  if (to.meta.guestOnly && isSignedIn.value) return '/app/home'
  if (to.meta.requiresAuth && !isSignedIn.value) return '/login'
})

export default router
