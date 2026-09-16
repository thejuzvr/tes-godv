import { useEffect, useRef, useCallback, useState } from "react"
import { api } from "@/lib/api"

interface WSMessage {
  type: string
  [key: string]: any
}

type MessageHandler = (data: WSMessage) => void

export function useWebSocket(token: string | null, heroId: string | null) {
  const wsRef = useRef<WebSocket | null>(null)
  const [connected, setConnected] = useState(false)
  const reconnectTimeout = useRef<ReturnType<typeof setTimeout> | null>(null)
  const reconnectAttempts = useRef(0)
  const handlersRef = useRef<Map<string, Set<MessageHandler>>>(new Map())
  const connectingRef = useRef(false)

  const on = useCallback((type: string, handler: MessageHandler) => {
    if (!handlersRef.current.has(type)) {
      handlersRef.current.set(type, new Set())
    }
    handlersRef.current.get(type)!.add(handler)
    return () => { handlersRef.current.get(type)?.delete(handler) }
  }, [])

  const connect = useCallback(() => {
    if (!token) return
    if (connectingRef.current) return
    if (wsRef.current?.readyState === WebSocket.OPEN) return

    // Close existing connection if any
    if (wsRef.current) {
      wsRef.current.close(1000, "Reconnecting")
      wsRef.current = null
    }

    connectingRef.current = true

    const isDev = import.meta.env.DEV
    const wsHost = isDev ? "localhost:4000" : window.location.host
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
    const wsUrl = `${protocol}//${wsHost}/socket/websocket?token=${encodeURIComponent(token)}`

    try {
      const ws = new WebSocket(wsUrl)
      wsRef.current = ws

      ws.onopen = () => {
        connectingRef.current = false
        setConnected(true)
        reconnectAttempts.current = 0

        // Join hero channel after connection
        if (token) {
          if (heroId) {
            const joinMsg = JSON.stringify({
              topic: `hero:${heroId}`,
              event: "phx_join",
              payload: { token: token },
              ref: "1",
            })
            ws.send(joinMsg)
          }

          // W-7: мировой канал (погода/цены/события/войны)
          const worldJoin = JSON.stringify({
            topic: "world:lobby",
            event: "phx_join",
            payload: {},
            ref: "2",
          })
          ws.send(worldJoin)
        }
      }

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)

          // Handle Phoenix Channel messages — dispatch ALL events (skip phx_* internals)
          if (data.event && !String(data.event).startsWith("phx_")) {
            const msg: WSMessage = {
              type: data.event,
              data: data.payload,
            }
            handlersRef.current.get(data.event)?.forEach(h => h(msg))
          }
        } catch (e) {
          // ignore parse errors
        }
      }

      ws.onclose = (event) => {
        // Stale socket: закрылся ПОСЛЕ открытия нового (смена heroId) — не трогаем состояние
        if (wsRef.current !== ws) return
        // 1000 = нормальное закрытие. Локальный disconnect() уже снял состояние
        // и отменил таймер, сюда попадаем только при СЕРВЕРНОМ close 1000
        // (рестарт Phoenix, idle-timeout) — статус уже «Переподключение…»,
        // без реконнекта он зависает навсегда. Планируем реконнект.
        if (event.code === 1000) {
          connectingRef.current = false
          setConnected(false)
          wsRef.current = null
          const delay = Math.min(5000 * Math.pow(2, reconnectAttempts.current), 30000)
          reconnectAttempts.current++
          reconnectTimeout.current = setTimeout(connect, delay)
          return
        }

        connectingRef.current = false
        setConnected(false)
        wsRef.current = null

        const delay = Math.min(5000 * Math.pow(2, reconnectAttempts.current), 30000)
        reconnectAttempts.current++
        reconnectTimeout.current = setTimeout(connect, delay)
      }

      ws.onerror = () => {
        // onclose will handle reconnection
      }
    } catch (e) {
      connectingRef.current = false
      console.error("[WS] Connection error:", e)
    }
  }, [token, heroId])

  const send = useCallback((data: any) => {
    if (wsRef.current?.readyState === WebSocket.OPEN && heroId) {
      // Send as Phoenix Channel message
      const msg = JSON.stringify({
        topic: `hero:${heroId}`,
        event: data.type || "message",
        payload: data,
        ref: Date.now().toString(),
      })
      wsRef.current.send(msg)
    }
  }, [heroId])

  const disconnect = useCallback(() => {
    connectingRef.current = false
    if (reconnectTimeout.current) {
      clearTimeout(reconnectTimeout.current)
      reconnectTimeout.current = null
    }
    if (wsRef.current) {
      wsRef.current.close(1000, "User disconnected")
      wsRef.current = null
    }
    setConnected(false)
  }, [])

  useEffect(() => {
    connect()
    return disconnect
  }, [connect, disconnect])

  // Мгновенный реконнект при возврате на вкладку / появлении сети:
  // браузер троттлит setTimeout в фоне (бэкофф до 30с «замирает»),
  // а возврат на вкладку должен поднимать сокет сразу, не через таймер.
  useEffect(() => {
    const reconnectNow = () => {
      if (!token) return
      if (wsRef.current?.readyState === WebSocket.OPEN) return
      if (wsRef.current?.readyState === WebSocket.CONNECTING) return
      if (connectingRef.current) return
      if (reconnectTimeout.current) {
        clearTimeout(reconnectTimeout.current)
        reconnectTimeout.current = null
      }
      reconnectAttempts.current = 0
      connect()
    }

    const onVisible = () => { if (document.visibilityState === "visible") reconnectNow() }
    document.addEventListener("visibilitychange", onVisible)
    window.addEventListener("online", reconnectNow)
    return () => {
      document.removeEventListener("visibilitychange", onVisible)
      window.removeEventListener("online", reconnectNow)
    }
  }, [connect, token])

  // REST-пульс как резерв is_online: WS-heartbeat живёт только пока сокет
  // открыт; если WS лежит (реконнект/деплой), герой не должен «умирать»
  // для воркера. sendBeacon/offline-флаг честно гасится через этот же путь.
  useEffect(() => {
    if (!token) return
    const pulse = () => { api.heartbeat().catch(() => {}) }
    pulse()
    const id = setInterval(pulse, 60_000)
    return () => clearInterval(id)
  }, [token])

  // Heartbeat via WebSocket every 30 seconds
  useEffect(() => {
    if (!connected) return
    const interval = setInterval(() => {
      send({ type: "heartbeat" })
    }, 30000)
    return () => clearInterval(interval)
  }, [connected, send])

  return { connected, send, disconnect, on }
}
