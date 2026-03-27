// middleware/auth.ts
export default defineNuxtRouteMiddleware(() => {
  const { isSignedIn } = useAuth()
  if (!isSignedIn.value) return navigateTo('/login')
})
