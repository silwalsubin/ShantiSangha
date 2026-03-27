import { useAuth } from '@clerk/vue'

export function useApi() {
  const { getToken } = useAuth()
  const base = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8080'

  async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const token = await getToken()
    const res = await fetch(`${base}${path}`, {
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
