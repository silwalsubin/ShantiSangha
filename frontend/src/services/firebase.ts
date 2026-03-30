/**
 * Firebase initialization and auth service.
 *
 * Single source of truth for Firebase configuration.
 * Provides auth state and token management for the API client.
 */

import { initializeApp } from 'firebase/app'
import {
  getAuth,
  GoogleAuthProvider,
  signInWithPopup,
  signOut as firebaseSignOut,
  onAuthStateChanged,
  type User,
} from 'firebase/auth'
import { ref } from 'vue'

const firebaseConfig = {
  apiKey: 'AIzaSyC46IbBPxeDbl9BPnZA_o5tUVof7-oMVSc',
  authDomain: 'shantisangha-bc0f9.firebaseapp.com',
  projectId: 'shantisangha-bc0f9',
  storageBucket: 'shantisangha-bc0f9.firebasestorage.app',
  messagingSenderId: '361305168424',
  appId: '1:361305168424:web:3a349cf196ec1a7369f31d',
}

const app = initializeApp(firebaseConfig)
export const auth = getAuth(app)

// Reactive auth state
export const currentUser = ref<User | null>(null)
export const authLoading = ref(true)

onAuthStateChanged(auth, (user) => {
  currentUser.value = user
  authLoading.value = false
})

export async function signInWithGoogle() {
  const provider = new GoogleAuthProvider()
  return signInWithPopup(auth, provider)
}

export async function signOut() {
  return firebaseSignOut(auth)
}

export async function getToken(): Promise<string | null> {
  const user = auth.currentUser
  if (!user) return null
  return user.getIdToken()
}
