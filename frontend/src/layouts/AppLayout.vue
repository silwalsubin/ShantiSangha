<script setup lang="ts">
import { useRoute, useRouter } from 'vue-router'
import { signOut, currentUser } from '@/services/firebase'
import SacredIcons from '@/components/icons/SacredIcons.vue'
import NotificationToast from '@/components/NotificationToast.vue'

const routerNav = useRouter()

async function handleSignOut() {
  await signOut()
  routerNav.push('/login')
}

const route = useRoute()

const navItems = [
  { icon: 'vajra', label: 'Home', href: '/app/home' },
  { icon: 'dialogue', label: 'Reflect', href: '/app/reflect' },
]

function isActive(href: string) {
  return route.path === href || route.path.startsWith(href + '/')
}
</script>

<template>
  <div class="min-h-screen bg-[linear-gradient(180deg,#faf5ed_0%,#f5ebe0_48%,#efe3d4_100%)] text-sacred-text">
    <!-- Desktop Sidebar -->
    <aside class="fixed inset-y-0 left-0 z-30 hidden w-56 flex-col border-r border-sacred-border-strong bg-sacred-bg-warm backdrop-blur-[20px] lg:flex">
      <!-- Logo -->
      <div class="flex h-20 items-center border-b border-sacred-border px-5">
        <RouterLink to="/app/home" class="flex items-center gap-3">
          <div class="logo-glow flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-br from-sacred-gold to-sacred-gold-dark text-white">
            <SacredIcons name="vajra" :size="28" />
          </div>
          <span class="font-serif text-lg font-bold tracking-wide text-sacred-text">ShantiSangha</span>
        </RouterLink>
      </div>

      <!-- Nav -->
      <nav class="flex-1 px-3 py-6">
        <ul class="space-y-1">
          <li v-for="item in navItems" :key="item.href">
            <RouterLink
              :to="item.href"
              class="group flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium transition-all duration-200"
              :class="isActive(item.href)
                ? 'bg-gradient-to-r from-sacred-gold-15 to-sacred-gold-05 text-sacred-gold-dark shadow-[inset_2px_0_0] shadow-sacred-gold'
                : 'text-sacred-text-secondary hover:bg-sacred-gold-light hover:text-sacred-text'"
            >
              <SacredIcons
                :name="item.icon"
                :size="20"
                class="shrink-0 transition-transform duration-200 group-hover:scale-110"
              />
              <span>{{ item.label }}</span>
            </RouterLink>
          </li>
        </ul>
      </nav>

      <!-- User -->
      <div class="border-t border-sacred-border px-5 py-4">
        <button @click="handleSignOut" class="flex items-center gap-2 text-xs text-sacred-muted hover:text-sacred-text transition">
          <img v-if="currentUser?.photoURL" :src="currentUser.photoURL" class="h-7 w-7 rounded-full" />
          <span v-else class="h-7 w-7 rounded-full bg-sacred-gold text-white flex items-center justify-center text-xs font-bold">{{ currentUser?.email?.[0]?.toUpperCase() }}</span>
        </button>
      </div>

      <!-- About link -->
      <div class="border-t border-sacred-border-light px-5 py-2">
        <RouterLink to="/app/about" class="text-[9px] tracking-wide text-sacred-muted-light hover:text-sacred-muted transition duration-200">
          About
        </RouterLink>
      </div>
    </aside>

    <!-- Main content -->
    <div class="lg:pl-56">
      <!-- Mobile top bar -->
      <div class="sticky top-0 z-20 flex h-14 items-center justify-between border-b border-sacred-border bg-sacred-bg-warm px-4 backdrop-blur-[20px] lg:hidden">
        <div class="flex items-center gap-2">
          <div class="logo-glow flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-sacred-gold to-sacred-gold-dark text-white">
            <SacredIcons name="vajra" :size="24" />
          </div>
          <span class="font-serif text-lg font-bold text-sacred-text">ShantiSangha</span>
        </div>
        <button @click="handleSignOut" class="flex items-center gap-2 text-xs text-sacred-muted hover:text-sacred-text transition">
          <img v-if="currentUser?.photoURL" :src="currentUser.photoURL" class="h-7 w-7 rounded-full" />
          <span v-else class="h-7 w-7 rounded-full bg-sacred-gold text-white flex items-center justify-center text-xs font-bold">{{ currentUser?.email?.[0]?.toUpperCase() }}</span>
        </button>
      </div>

      <main class="min-h-screen">
        <RouterView v-slot="{ Component }">
          <Transition name="fade" mode="out-in">
            <component :is="Component" />
          </Transition>
        </RouterView>
      </main>

      <!-- Mobile bottom tab bar -->
      <nav class="fixed inset-x-0 bottom-0 z-30 flex border-t border-sacred-border-strong bg-[rgba(250,245,237,0.97)] backdrop-blur-[20px] lg:hidden">
        <RouterLink
          v-for="item in navItems"
          :key="item.href"
          :to="item.href"
          class="flex flex-1 flex-col items-center gap-1 py-3 text-[10px] font-medium tracking-wide transition-colors"
          :class="isActive(item.href)
            ? 'text-sacred-gold-dark'
            : 'text-sacred-muted'"
        >
          <SacredIcons :name="item.icon" :size="22" />
          <span>{{ item.label }}</span>
        </RouterLink>
      </nav>

      <!-- Mobile bottom spacer -->
      <div class="h-20 lg:hidden" />
    </div>
  </div>
  <NotificationToast />
</template>

<style scoped>
.logo-glow {
  animation: sacred-glow 3s ease-in-out infinite;
}

/* Animation keyframes use raw rgba -- these are CSS-only values, not Tailwind classes */
@keyframes sacred-glow {
  0%, 100% {
    box-shadow: 0 0 8px rgba(196, 135, 59, 0.3), 0 0 20px rgba(196, 135, 59, 0.1);
  }
  50% {
    box-shadow: 0 0 16px rgba(196, 135, 59, 0.5), 0 0 40px rgba(196, 135, 59, 0.2);
  }
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.15s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
