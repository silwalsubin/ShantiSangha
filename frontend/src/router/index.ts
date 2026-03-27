import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from '@clerk/vue'
import { watch } from 'vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/app/dashboard' },
    { path: '/login', component: () => import('@/pages/login.vue'), meta: { guestOnly: true } },
    { path: '/signup', component: () => import('@/pages/signup.vue'), meta: { guestOnly: true } },
    {
      path: '/app',
      component: () => import('@/layouts/AppLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        { path: 'dashboard', component: () => import('@/pages/app/dashboard.vue') },
        { path: 'chat', component: () => import('@/pages/app/chat/index.vue') },
        { path: 'chat/:id', component: () => import('@/pages/app/chat/[id].vue') },
        { path: 'journal', component: () => import('@/pages/app/journal/index.vue') },
        { path: 'journal/new', component: () => import('@/pages/app/journal/new.vue') },
        { path: 'journal/:id', component: () => import('@/pages/app/journal/[id].vue') },
        { path: 'mood', component: () => import('@/pages/app/mood/index.vue') },
        { path: 'coping', component: () => import('@/pages/app/coping/index.vue') },
        { path: 'insights', component: () => import('@/pages/app/insights/index.vue') },
        { path: 'voice', component: () => import('@/pages/app/voice/index.vue') },
        { path: '', redirect: 'dashboard' }
      ]
    }
  ]
})

router.beforeEach(async (to) => {
  const { isSignedIn, isLoaded } = useAuth()
  // Wait for Clerk to initialize
  if (!isLoaded.value) {
    await new Promise<void>(resolve => {
      const unwatch = watch(isLoaded, (val) => { if (val) { unwatch(); resolve() } })
    })
  }
  // Redirect authenticated users away from login/signup
  if (to.meta.guestOnly && isSignedIn.value) return '/app/dashboard'
  // Redirect unauthenticated users to login
  if (to.meta.requiresAuth && !isSignedIn.value) return '/login'
})

export default router
