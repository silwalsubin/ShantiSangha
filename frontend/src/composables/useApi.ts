import { useAuth } from '@clerk/vue'

export function useApi() {
  const { getToken } = useAuth()
  const base = import.meta.env.VITE_API_BASE_URL || '/api'

  async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const url = `${base}${path}`
    console.log(`[API] ${method} ${url}`)
    let token: string | null = null
    try {
      token = await getToken()
    } catch (e) {
      console.error('[API] getToken() failed:', e)
    }
    const res = await fetch(url, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    })
    if (!res.ok) throw new Error(`API error ${res.status}`)
    if (res.status === 204) return undefined as T
    return res.json()
  }

  return {
    get: <T>(path: string) => request<T>('GET', path),
    post: <T>(path: string, body?: unknown) => request<T>('POST', path, body),
    patch: <T>(path: string, body: unknown) => request<T>('PATCH', path, body),
    delete: <T>(path: string) => request<T>('DELETE', path),
    base,
    getToken,
  }
}
