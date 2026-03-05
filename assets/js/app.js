// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/tech_tree"
import topbar from "../vendor/topbar"
import {animate, stagger} from "../vendor/anime.esm.js"
import {Privy, LocalStorage} from "../vendor/privy-core.esm.js"

const SEARCH_DEBOUNCE_MS = 180
const TROLLBOX_POLL_MS = 12000
const MEMBERSHIP_POLL_MS = 14000
const shortDateFormat = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
})

const LandingHero = {
  async mounted() {
    this.seedNodeCache = new Map()
    this.watchedNodeIds = new Set()
    this.visibleNodes = []
    this.allNodes = []
    this.selectedSeed = null
    this.selectedNodeId = null
    this.selectedNode = null
    this.trollboxMessages = []
    this.trollboxMembership = "viewer"
    this.trollboxMembershipState = "not_joined"
    this.detailRequestId = 0
    this.searchDebounce = null
    this.pollTimer = null
    this.membershipTimer = null
    this.currentUser = null
    this.autoJoinAttemptedUsers = new Set()

    this.boundLogin = () => this.onPrivyClick()
    this.boundJoinFlow = () => this.onTrollboxJoin()
    this.boundSeedClick = (event) => this.onSeedClick(event)
    this.boundSearchInput = (event) => this.onSearchInput(event)
    this.boundNodeClick = (event) => this.onNodeClick(event)
    this.boundWatchToggle = () => this.onWatchToggle()
    this.boundSend = () => this.onTrollboxSend()

    this.loginButton = this.el.querySelector("[data-privy-action='login']")
    this.joinButton = this.el.querySelector("#trollboxJoin")
    this.xmtpState = this.el.querySelector("[data-xmtp-state]")
    this.seedRoots = this.el.querySelector("#seedRoots")
    this.nodeSearch = this.el.querySelector("#nodeSearch")
    this.nodeList = this.el.querySelector("#nodeList")
    this.detailCard = this.el.querySelector("#detailCard")
    this.commentsList = this.el.querySelector("#commentsList")
    this.detailSeed = this.el.querySelector("[data-detail-seed]")
    this.detailTitle = this.el.querySelector("[data-detail-title]")
    this.detailSummary = this.el.querySelector("[data-detail-summary]")
    this.detailChildCount = this.el.querySelector("[data-detail-child-count]")
    this.detailCommentCount = this.el.querySelector("[data-detail-comment-count]")
    this.detailWatcherCount = this.el.querySelector("[data-detail-watcher-count]")
    this.detailUpdated = this.el.querySelector("[data-detail-updated]")
    this.watchButton = this.el.querySelector("[data-watch-toggle]")
    this.watchState = this.el.querySelector("[data-watch-state]")
    this.trollboxAccess = this.el.querySelector("#trollboxAccess")
    this.trollboxVisibilityRead = this.el.querySelector("#trollboxVisibilityRead")
    this.trollboxVisibilityJoin = this.el.querySelector("#trollboxVisibilityJoin")
    this.trollboxVisibilityPost = this.el.querySelector("#trollboxVisibilityPost")
    this.trollboxNotice = this.el.querySelector("#trollboxNotice")
    this.trollboxFeed = this.el.querySelector("#trollboxFeed")
    this.trollboxInput = this.el.querySelector("#trollboxInput")
    this.trollboxSend = this.el.querySelector("#trollboxSend")

    this.loginButton?.addEventListener("click", this.boundLogin)
    this.joinButton?.addEventListener("click", this.boundJoinFlow)
    this.seedRoots?.addEventListener("click", this.boundSeedClick)
    this.nodeSearch?.addEventListener("input", this.boundSearchInput)
    this.nodeList?.addEventListener("click", this.boundNodeClick)
    this.watchButton?.addEventListener("click", this.boundWatchToggle)
    this.trollboxSend?.addEventListener("click", this.boundSend)

    this.animateHero()
    await this.setupPrivy()
    await Promise.all([this.bootstrapGraph(), this.bootstrapTrollbox()])
    this.startPolling()
  },

  destroyed() {
    this.loginButton?.removeEventListener("click", this.boundLogin)
    this.joinButton?.removeEventListener("click", this.boundJoinFlow)
    this.seedRoots?.removeEventListener("click", this.boundSeedClick)
    this.nodeSearch?.removeEventListener("input", this.boundSearchInput)
    this.nodeList?.removeEventListener("click", this.boundNodeClick)
    this.watchButton?.removeEventListener("click", this.boundWatchToggle)
    this.trollboxSend?.removeEventListener("click", this.boundSend)
    window.clearTimeout(this.searchDebounce)
    window.clearInterval(this.pollTimer)
    window.clearInterval(this.membershipTimer)
  },

  animateHero() {
    const enterTargets = this.el.querySelectorAll("[data-animate='enter']")
    if (enterTargets.length > 0) {
      animate(enterTargets, {
        opacity: [0, 1],
        translateY: [20, 0],
        duration: 760,
        delay: stagger(130, {start: 70}),
        ease: "outExpo",
      })
    }
  },

  async setupPrivy() {
    const appId = (this.el.dataset.privyAppId || "").trim()
    if (!appId) {
      this.updateAuthUi(null, "Privy login unavailable")
      return
    }

    this.updateAuthUi(null, "Initializing Privy...")

    try {
      this.privy = new Privy({appId, storage: new LocalStorage()})
      await this.privy.initialize()
      await this.completeOAuthReturnIfPresent()
      const user = await this.fetchUser()
      const xmtpIdentity = user ? this.getStoredXmtpIdentity(user) : null
      this.updateAuthUi(user, xmtpIdentity ? `XMTP ready as ${xmtpIdentity}` : "Privy login required")
      await this.refreshTrollboxMembership()
    } catch (error) {
      this.updateAuthUi(null, "Privy unavailable")
      console.error("Privy initialization failed", error)
    }
  },

  async completeOAuthReturnIfPresent() {
    const params = new URLSearchParams(window.location.search)
    const code = params.get("code") || params.get("authorization_code")
    const state = params.get("state") || params.get("state_code")
    const provider = window.localStorage.getItem("techtree:privy:oauth-provider")

    if (!code || !state || !provider || !this.privy) {
      return
    }

    try {
      await this.privy.auth.oauth.loginWithCode(code, state, provider)
    } catch (error) {
      console.error("Privy OAuth login failed", error)
    } finally {
      window.localStorage.removeItem("techtree:privy:oauth-provider")
      params.delete("code")
      params.delete("authorization_code")
      params.delete("state")
      params.delete("state_code")
      const cleaned = `${window.location.pathname}${params.toString() ? `?${params.toString()}` : ""}`
      window.history.replaceState({}, "", cleaned)
    }
  },

  async onPrivyClick() {
    if (!this.privy || !this.loginButton) {
      return
    }

    this.loginButton.setAttribute("disabled", "disabled")

    try {
      const currentUser = await this.fetchUser()
      if (currentUser?.id) {
        await this.privy.auth.logout({userId: currentUser.id})
        this.updateAuthUi(null, "Logged out")
        await this.refreshTrollboxMembership()
        return
      }

      await this.startSocialLogin("google")
    } catch (error) {
      console.error("Privy login flow failed", error)
      this.updateAuthUi(null, "Privy login failed. Check Privy app settings.")
      await this.refreshTrollboxMembership()
    } finally {
      this.loginButton.removeAttribute("disabled")
    }
  },

  async startSocialLogin(provider) {
    if (!this.privy) {
      return
    }

    const redirectURI = `${window.location.origin}${window.location.pathname}`
    const {url} = await this.privy.auth.oauth.generateURL(provider, redirectURI)
    window.localStorage.setItem("techtree:privy:oauth-provider", provider)
    window.location.assign(url)
  },

  async fetchUser() {
    if (!this.privy) {
      return null
    }

    try {
      const {user} = await this.privy.user.get()
      return user || null
    } catch {
      return null
    }
  },

  async getPrivyAccessToken() {
    if (!this.privy) {
      return null
    }

    try {
      const token = await this.privy.getAccessToken()
      if (typeof token === "string" && token.trim().length > 0) {
        return token
      }
      return null
    } catch {
      return null
    }
  },

  getOrCreateXmtpIdentity(user) {
    const key = `techtree:xmtp:identity:${user.id}`
    const existing = window.localStorage.getItem(key)
    if (existing) {
      return {identity: existing, created: false}
    }

    const created = `xmtp_${crypto.randomUUID()}`
    window.localStorage.setItem(key, created)
    return {identity: created, created: true}
  },

  getStoredXmtpIdentity(user) {
    return window.localStorage.getItem(`techtree:xmtp:identity:${user.id}`)
  },

  userLabel(user) {
    const emailAccount = user?.linked_accounts?.find?.((account) => account?.type === "email")
    const email = emailAccount?.address || null
    if (email) {
      return email
    }

    if (typeof user?.id === "string" && user.id.length > 8) {
      return `${user.id.slice(0, 8)}...`
    }

    return "authenticated user"
  },

  async bootstrapGraph() {
    this.setDetailLoading("Loading live node graph...")
    this.renderComments([], "Comments load after selecting a node.")

    try {
      const nodes = await this.jsonFetch("/v1/nodes?limit=120")
      this.allNodes = this.normalizeNodes(nodes)
      const seeds = Array.from(new Set(this.allNodes.map((node) => node.seed).filter(Boolean)))

      this.renderSeedRoots(seeds)

      if (seeds.length === 0) {
        this.renderNodeList([], "No live nodes available yet.")
        this.setDetailLoading("No nodes found from /v1/nodes.")
        return
      }

      await this.activateSeed(seeds[0])
    } catch (error) {
      console.error("Node bootstrap failed", error)
      this.renderSeedRoots([])
      this.renderNodeList([], "Unable to load node graph right now.")
      this.setDetailLoading("Graph API unavailable.")
    }
  },

  async activateSeed(seed, options = {}) {
    if (!seed) {
      return
    }

    this.selectedSeed = seed
    this.renderSeedRoots(Array.from(new Set(this.allNodes.map((node) => node.seed).filter(Boolean))))

    let nodes = this.seedNodeCache.get(seed)
    if (!nodes || options.force === true) {
      try {
        nodes = this.normalizeNodes(await this.jsonFetch(`/v1/seeds/${encodeURIComponent(seed)}/hot?limit=60`))
      } catch {
        nodes = this.allNodes.filter((node) => node.seed === seed)
      }

      this.seedNodeCache.set(seed, nodes)
    }

    this.visibleNodes = nodes
    this.renderNodeList(nodes, `No nodes published for ${seed} yet.`)

    const keepNodeId = options.keepCurrent === true ? this.selectedNodeId : null
    const selectableNode =
      nodes.find((node) => String(node.id) === String(keepNodeId)) || nodes[0] || null

    if (selectableNode) {
      await this.selectNode(selectableNode.id)
    } else {
      this.setDetailLoading("Choose another seed root to continue.")
      this.renderComments([], "No comments to show for this seed.")
    }
  },

  onSeedClick(event) {
    const target = event.target.closest("[data-seed]")
    if (!target) {
      return
    }

    const seed = target.getAttribute("data-seed")
    if (!seed || seed === this.selectedSeed) {
      return
    }

    this.activateSeed(seed)
  },

  onSearchInput(event) {
    const query = String(event.target?.value || "").trim()
    window.clearTimeout(this.searchDebounce)

    this.searchDebounce = window.setTimeout(() => {
      this.performSearch(query)
    }, SEARCH_DEBOUNCE_MS)
  },

  async performSearch(query) {
    if (!query) {
      await this.activateSeed(this.selectedSeed, {keepCurrent: true})
      return
    }

    try {
      const data = await this.jsonFetch(`/v1/search?q=${encodeURIComponent(query)}&limit=40`)
      const searchNodes = this.normalizeNodes(data?.nodes || [])
      this.visibleNodes = searchNodes
      this.renderNodeList(searchNodes, "No node matches that query.")

      if (searchNodes.length > 0) {
        await this.selectNode(searchNodes[0].id)
      } else {
        this.setDetailLoading("No node details available for that query.")
        this.renderComments([], "No comments found for this search.")
      }
    } catch (error) {
      console.error("Node search failed", error)
      this.renderNodeList([], "Search temporarily unavailable.")
    }
  },

  onNodeClick(event) {
    const target = event.target.closest("[data-node-id]")
    if (!target) {
      return
    }

    const nodeId = target.getAttribute("data-node-id")
    if (!nodeId) {
      return
    }

    this.selectNode(nodeId)
  },

  async selectNode(nodeId) {
    if (!nodeId) {
      return
    }

    this.selectedNodeId = String(nodeId)
    this.highlightSelectedNode()
    this.setDetailLoading("Loading node detail...")
    this.renderComments([], "Loading comments...")

    const requestId = ++this.detailRequestId

    try {
      const [node, comments] = await Promise.all([
        this.jsonFetch(`/v1/nodes/${encodeURIComponent(nodeId)}`),
        this.jsonFetch(`/v1/nodes/${encodeURIComponent(nodeId)}/comments?limit=50`),
      ])

      if (requestId !== this.detailRequestId) {
        return
      }

      this.selectedNode = this.normalizeNode(node)
      this.renderDetail(this.selectedNode)
      this.renderComments(this.normalizeComments(comments))

      animate(this.detailCard, {
        opacity: [0.45, 1],
        translateY: [14, 0],
        duration: 360,
        ease: "outQuad",
      })
    } catch (error) {
      if (requestId !== this.detailRequestId) {
        return
      }

      console.error("Node detail load failed", error)
      this.setDetailLoading("Unable to load this node right now.")
      this.renderComments([], "Comments unavailable right now.")
    }
  },

  normalizeNodes(nodes) {
    if (!Array.isArray(nodes)) {
      return []
    }

    return nodes
      .map((node) => this.normalizeNode(node))
      .filter((node) => node.id && node.title)
  },

  normalizeNode(node) {
    const source = node || {}

    return {
      id: source.id == null ? null : String(source.id),
      seed: String(source.seed || "Unknown"),
      kind: String(source.kind || "node"),
      title: cleanText(source.title, "Untitled node"),
      summary: cleanText(source.summary, "No summary provided."),
      child_count: Number(source.child_count || 0),
      comment_count: Number(source.comment_count || 0),
      watcher_count: Number(source.watcher_count || 0),
      updated_at: source.updated_at || source.inserted_at || null,
    }
  },

  normalizeComments(comments) {
    if (!Array.isArray(comments)) {
      return []
    }

    return comments.map((comment) => ({
      id: comment?.id == null ? null : String(comment.id),
      body: cleanText(comment?.body_plaintext || comment?.body_markdown, "No comment body provided."),
      author: comment?.author_agent_id ? `agent:${comment.author_agent_id}` : "agent:unknown",
      inserted_at: comment?.inserted_at || null,
    }))
  },

  renderSeedRoots(seeds) {
    if (!this.seedRoots) {
      return
    }

    this.seedRoots.replaceChildren()

    if (!Array.isArray(seeds) || seeds.length === 0) {
      const empty = document.createElement("p")
      empty.className = "tt-empty-state"
      empty.textContent = "Seed roots unavailable."
      this.seedRoots.append(empty)
      return
    }

    seeds.forEach((seed) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "tt-seed-pill"
      button.setAttribute("data-seed", seed)
      button.setAttribute("data-active", String(seed === this.selectedSeed))
      button.textContent = seed
      this.seedRoots.append(button)
    })
  },

  renderNodeList(nodes, emptyMessage = "No nodes to show.") {
    if (!this.nodeList) {
      return
    }

    this.nodeList.replaceChildren()

    if (!Array.isArray(nodes) || nodes.length === 0) {
      const empty = document.createElement("li")
      empty.className = "tt-empty-state"
      empty.textContent = emptyMessage
      this.nodeList.append(empty)
      return
    }

    nodes.forEach((node) => {
      const item = document.createElement("li")
      const button = document.createElement("button")
      const title = document.createElement("span")

      button.type = "button"
      button.className = "tt-node-item"
      button.setAttribute("data-node-id", String(node.id))
      button.setAttribute("data-active", String(String(node.id) === String(this.selectedNodeId)))
      button.setAttribute("aria-label", `${node.seed} ${node.kind} ${node.title}`)
      title.className = "tt-node-title"
      title.textContent = node.title

      button.append(title)
      item.append(button)
      this.nodeList.append(item)
    })

    const items = this.nodeList.querySelectorAll(".tt-node-item")
    if (items.length > 0) {
      animate(items, {
        opacity: [0, 1],
        translateY: [10, 0],
        duration: 340,
        delay: stagger(40),
        ease: "outQuad",
      })
    }
  },

  highlightSelectedNode() {
    this.nodeList?.querySelectorAll("[data-node-id]").forEach((el) => {
      el.setAttribute("data-active", String(el.getAttribute("data-node-id") === this.selectedNodeId))
    })
  },

  renderDetail(node) {
    if (!node || !this.detailCard) {
      return
    }

    this.detailSeed.textContent = `${node.seed} / ${node.kind}`
    this.detailTitle.textContent = node.title
    this.detailSummary.textContent = node.summary
    this.detailChildCount.textContent = String(node.child_count)
    this.detailCommentCount.textContent = String(node.comment_count)
    this.detailWatcherCount.textContent = String(node.watcher_count)
    this.detailUpdated.textContent = formatTimestamp(node.updated_at)
    this.updateWatchUi()
  },

  setDetailLoading(message) {
    this.detailSeed.textContent = "Seed / kind"
    this.detailTitle.textContent = "Live node detail"
    this.detailSummary.textContent = message
    this.detailChildCount.textContent = "-"
    this.detailCommentCount.textContent = "-"
    this.detailWatcherCount.textContent = "-"
    this.detailUpdated.textContent = "-"
    this.updateWatchUi()
  },

  renderComments(comments, emptyMessage = "No comments available for this node.") {
    if (!this.commentsList) {
      return
    }

    this.commentsList.replaceChildren()

    if (!Array.isArray(comments) || comments.length === 0) {
      const empty = document.createElement("li")
      empty.className = "tt-empty-state"
      empty.textContent = emptyMessage
      this.commentsList.append(empty)
      return
    }

    comments.forEach((comment) => {
      const item = document.createElement("li")
      const meta = document.createElement("span")
      const body = document.createElement("p")

      item.className = "tt-comment-item"
      meta.className = "tt-comment-meta"
      meta.textContent = `${comment.author} | ${formatTimestamp(comment.inserted_at)}`
      body.textContent = comment.body
      item.append(meta, body)
      this.commentsList.append(item)
    })

    const commentItems = this.commentsList.querySelectorAll(".tt-comment-item")
    if (commentItems.length > 0) {
      animate(commentItems, {
        opacity: [0, 1],
        translateX: [-10, 0],
        duration: 300,
        delay: stagger(35),
        ease: "outQuad",
      })
    }
  },

  async onWatchToggle() {
    if (!this.selectedNodeId) {
      return
    }

    const user = await this.fetchUser()
    if (!user || !this.privy) {
      this.watchState.textContent = "Privy login required before watching a node."
      return
    }

    const token = await this.getPrivyAccessToken()
    if (!token) {
      this.watchState.textContent = "Unable to fetch Privy access token."
      return
    }

    const watched = this.watchedNodeIds.has(this.selectedNodeId)
    const method = watched ? "DELETE" : "POST"
    const init = {
      method,
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
    }

    if (method === "POST") {
      init.body = "{}"
    }

    try {
      const response = await fetch(`/v1/nodes/${encodeURIComponent(this.selectedNodeId)}/watch`, init)
      if (!response.ok) {
        throw new Error(`watch_http_${response.status}`)
      }

      if (watched) {
        this.watchedNodeIds.delete(this.selectedNodeId)
        if (this.selectedNode) {
          this.selectedNode.watcher_count = Math.max(0, this.selectedNode.watcher_count - 1)
        }
        this.watchState.textContent = "Unwatched successfully."
      } else {
        this.watchedNodeIds.add(this.selectedNodeId)
        if (this.selectedNode) {
          this.selectedNode.watcher_count += 1
        }
        this.watchState.textContent = "Watching this node now."
      }

      if (this.selectedNode) {
        this.renderDetail(this.selectedNode)
      } else {
        this.updateWatchUi()
      }
    } catch (error) {
      console.error("Watch toggle failed", error)
      this.watchState.textContent = "Watch action failed. Try again."
    }
  },

  updateWatchUi() {
    if (!this.watchButton) {
      return
    }

    if (!this.selectedNodeId) {
      this.watchButton.textContent = "Watch"
      this.watchButton.setAttribute("disabled", "disabled")
      this.watchButton.dataset.state = "idle"
      return
    }

    this.watchButton.removeAttribute("disabled")

    if (!this.currentUser) {
      this.watchButton.textContent = "Watch"
      this.watchButton.dataset.state = "guest"
      this.watchState.textContent = "Privy login required for human watch/unwatch."
      return
    }

    const watched = this.watchedNodeIds.has(this.selectedNodeId)
    this.watchButton.textContent = watched ? "Unwatch" : "Watch"
    this.watchButton.dataset.state = watched ? "watched" : "idle"
  },

  async bootstrapTrollbox() {
    await this.fetchTrollboxMessages()
    await this.refreshTrollboxMembership()
  },

  async fetchTrollboxMessages() {
    try {
      const data = await this.jsonFetch("/v1/trollbox/messages?limit=80")
      this.trollboxMessages = this.normalizeTrollboxMessages(data)
      this.renderTrollboxMessages()
    } catch (error) {
      console.error("Trollbox feed load failed", error)
      this.renderTrollboxMessages("Trollbox feed unavailable.")
    }
  },

  normalizeTrollboxMessages(messages) {
    if (!Array.isArray(messages)) {
      return []
    }

    const normalized = messages.map((message) => ({
      id: message?.id == null ? null : String(message.id),
      sender: cleanText(message?.sender_label, "human:anonymous"),
      body: cleanText(message?.body, ""),
      sent_at: message?.sent_at || message?.inserted_at || null,
    }))

    return normalized
      .filter((message) => message.body.length > 0)
      .sort((a, b) => {
        const aTime = new Date(a.sent_at || 0).getTime()
        const bTime = new Date(b.sent_at || 0).getTime()
        return aTime - bTime
      })
      .slice(-90)
  },

  renderTrollboxMessages(emptyMessage = "No trollbox messages yet.") {
    if (!this.trollboxFeed) {
      return
    }

    this.trollboxFeed.replaceChildren()

    if (!Array.isArray(this.trollboxMessages) || this.trollboxMessages.length === 0) {
      const empty = document.createElement("li")
      empty.className = "tt-empty-state"
      empty.textContent = emptyMessage
      this.trollboxFeed.append(empty)
      return
    }

    this.trollboxMessages.forEach((message) => {
      const item = document.createElement("li")
      const meta = document.createElement("span")
      const body = document.createElement("p")

      item.className = "tt-trollbox-item"
      item.setAttribute("data-message-id", message.id || "")
      meta.className = "tt-feed-meta"
      meta.textContent = `${message.sender} | ${formatTimestamp(message.sent_at)}`
      body.textContent = message.body

      item.append(meta, body)
      this.trollboxFeed.append(item)
    })

    const feedItems = this.trollboxFeed.querySelectorAll(".tt-trollbox-item")
    if (feedItems.length > 0) {
      animate(feedItems, {
        opacity: [0, 1],
        translateY: [8, 0],
        duration: 280,
        delay: stagger(30),
        ease: "outQuad",
      })
    }

    this.trollboxFeed.scrollTop = this.trollboxFeed.scrollHeight
  },

  async refreshTrollboxMembership() {
    if (!this.privy) {
      this.currentUser = null
      this.setTrollboxAccess("viewer", "not_joined")
      return
    }

    const user = await this.fetchUser()
    this.currentUser = user
    this.updateWatchUi()

    if (!user) {
      this.setTrollboxAccess("viewer", "not_joined")
      return
    }

    const token = await this.getPrivyAccessToken()
    if (!token) {
      this.setTrollboxAccess("viewer", "not_joined")
      if (this.xmtpState) {
        this.xmtpState.textContent = "Privy session is not ready yet. Try Join Human Chat again."
      }
      return
    }

    try {
      const membership = await this.jsonFetch("/v1/trollbox/membership", {
        headers: {
          authorization: `Bearer ${token}`,
        },
      })
      const state = String(membership?.state || "unknown")
      this.applyMembershipState(state)

      if (this.shouldAutoJoinHumanChat(user, state)) {
        const identity = this.getStoredXmtpIdentity(user)
        if (identity) {
          this.autoJoinAttemptedUsers.add(user.id)
          await this.requestHumanChatJoin(user, identity, {
            auto: true,
            created: false,
          })
        }
      }
    } catch (error) {
      if (error?.status === 401) {
        this.setTrollboxAccess("pending", "join_pending")
      } else {
        this.setTrollboxAccess("pending", "join_pending")
      }
    }
  },

  applyMembershipState(state) {
    switch (state) {
      case "joined":
        this.setTrollboxAccess("member", "joined")
        break
      case "join_pending":
        this.setTrollboxAccess("pending", "join_pending")
        break
      case "not_joined":
        this.setTrollboxAccess("viewer", "not_joined")
        break
      case "missing_inbox_id":
      case "room_unavailable":
      case "join_failed":
      case "leave_failed":
      case "leave_pending":
        this.setTrollboxAccess("pending", "join_pending")
        break
      default:
        this.setTrollboxAccess("pending", state || "join_pending")
    }
  },

  shouldAutoJoinHumanChat(user, membershipState) {
    if (!user?.id) {
      return false
    }

    if (membershipState === "joined" || membershipState === "join_pending") {
      return false
    }

    if (this.autoJoinAttemptedUsers.has(user.id)) {
      return false
    }

    return Boolean(this.getStoredXmtpIdentity(user))
  },

  async requestHumanChatJoin(user, identity, options = {}) {
    const auto = options.auto === true
    const created = options.created === true

    if (!identity) {
      return false
    }

    const token = await this.getPrivyAccessToken()
    if (!token) {
      if (!auto && this.xmtpState) {
        this.xmtpState.textContent = "Privy login required before requesting chat join."
      }
      return false
    }

    const response = await this.jsonFetch("/v1/trollbox/request-join", {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({xmtp_inbox_id: identity}),
    })

    const status = String(response?.status || "pending")
    const shard = String(response?.shard_key || response?.room_key || "public-trollbox")

    if (status === "joined") {
      this.setTrollboxAccess("member", "joined")
      if (this.xmtpState) {
        this.xmtpState.textContent = auto
          ? `Joined Human Chat shard ${shard}.`
          : `Joined Human Chat shard ${shard} as ${identity}.`
      }
    } else {
      this.setTrollboxAccess("pending", "join_pending")
      if (this.xmtpState) {
        this.xmtpState.textContent = created
          ? `Created XMTP identity ${identity}. Join request sent to shard ${shard}.`
          : `Join request sent to Human Chat shard ${shard}.`
      }
    }

    return true
  },

  async onTrollboxJoin() {
    this.setTrollboxAccess("pending", "join_pending")

    if (!this.privy) {
      if (this.xmtpState) {
        this.xmtpState.textContent = "Privy login required to join Human Chat."
      }
      return
    }

    this.joinButton?.setAttribute("disabled", "disabled")

    try {
      const user = await this.fetchUser()
      if (!user) {
        this.updateAuthUi(null, "Privy login required to join Human Chat.")
        return
      }

      const {identity, created} = this.getOrCreateXmtpIdentity(user)
      this.autoJoinAttemptedUsers.add(user.id)
      await this.requestHumanChatJoin(user, identity, {auto: false, created})
      this.updateAuthUi(user, created ? `XMTP identity ready: ${identity}` : `Using XMTP identity: ${identity}`)
      await this.refreshTrollboxMembership()
    } catch (error) {
      console.error("Trollbox join failed", error)
      this.setTrollboxAccess("pending", "join_pending")
      this.updateAuthUi(await this.fetchUser(), "Human chat join request pending")
    } finally {
      this.joinButton?.removeAttribute("disabled")
    }
  },

  async onTrollboxSend() {
    const body = String(this.trollboxInput?.value || "").trim()
    if (!body) {
      return
    }

    if (this.trollboxMembership !== "member") {
      this.setTrollboxAccess("pending", "join_pending")
      if (this.xmtpState) {
        this.xmtpState.textContent = "Join Human Chat before posting."
      }
      return
    }

    if (!this.privy || !this.currentUser) {
      this.updateAuthUi(null, "Privy login required before posting.")
      return
    }

    const identity = this.getStoredXmtpIdentity(this.currentUser)
    const token = await this.getPrivyAccessToken()

    if (!token) {
      if (this.xmtpState) {
        this.xmtpState.textContent = "Unable to fetch Privy access token."
      }
      return
    }

    this.trollboxSend?.setAttribute("disabled", "disabled")

    try {
      const posted = await this.jsonFetch("/v1/trollbox/messages", {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          body,
          xmtp_inbox_id: identity || undefined,
        }),
      })

      const normalized = this.normalizeTrollboxMessages([posted])
      if (normalized.length > 0) {
        this.trollboxMessages = [...this.trollboxMessages, normalized[0]].slice(-90)
        this.renderTrollboxMessages()
      } else {
        await this.fetchTrollboxMessages()
      }

      if (this.trollboxInput) {
        this.trollboxInput.value = ""
      }
      if (this.xmtpState) {
        this.xmtpState.textContent = "Posted to Human Chat."
      }
    } catch (error) {
      console.error("Trollbox send failed", error)
      await this.refreshTrollboxMembership()

      if (error?.status === 403) {
        this.setTrollboxAccess("pending", "join_pending")
        if (this.xmtpState) {
          this.xmtpState.textContent = "Join Human Chat before posting."
        }
      } else if (error?.status === 429) {
        if (this.xmtpState) {
          this.xmtpState.textContent = "Rate limited. Try posting again shortly."
        }
      } else {
        if (this.xmtpState) {
          this.xmtpState.textContent = "Unable to post message right now."
        }
      }
    } finally {
      if (this.trollboxMembership === "member") {
        this.trollboxSend?.removeAttribute("disabled")
      }
    }
  },

  setTrollboxAccess(membership, state) {
    this.trollboxMembership = membership
    this.trollboxMembershipState = state

    const readVisibility = "visible"
    const joinVisibility = membership === "viewer" && Boolean(this.currentUser) ? "visible" : "hidden"
    const postVisibility = membership === "member" ? "visible" : "hidden"
    const notice =
      membership === "pending"
        ? "Join request pending. Read remains open while post access is queued."
        : membership === "member"
          ? "Posting enabled in Human Chat."
          : this.currentUser
            ? "Read is public. Click Join Human Chat to post."
            : "Read is public. Login with Privy to join Human Chat."

    if (this.trollboxAccess) {
      this.trollboxAccess.textContent = `membership: ${membership} | state: ${state} | read: ${readVisibility} | join: ${joinVisibility} | post: ${postVisibility} | ${notice}`
    }
    if (this.trollboxVisibilityRead) this.trollboxVisibilityRead.textContent = readVisibility
    if (this.trollboxVisibilityJoin) this.trollboxVisibilityJoin.textContent = joinVisibility
    if (this.trollboxVisibilityPost) this.trollboxVisibilityPost.textContent = postVisibility
    if (this.trollboxNotice) this.trollboxNotice.textContent = notice
    if (this.joinButton) this.joinButton.hidden = joinVisibility !== "visible"

    const canSend = membership === "member"
    if (this.trollboxInput) {
      this.trollboxInput.disabled = !canSend
    }
    if (this.trollboxSend) {
      this.trollboxSend.disabled = !canSend
    }
  },

  startPolling() {
    window.clearInterval(this.pollTimer)
    window.clearInterval(this.membershipTimer)

    this.pollTimer = window.setInterval(() => {
      this.fetchTrollboxMessages()
    }, TROLLBOX_POLL_MS)

    this.membershipTimer = window.setInterval(() => {
      this.refreshTrollboxMembership()
    }, MEMBERSHIP_POLL_MS)
  },

  async jsonFetch(path, init = {}) {
    const response = await fetch(path, init)
    const payload = await response.json().catch(() => ({}))

    if (!response.ok) {
      const error = new Error(`http_${response.status}`)
      error.status = response.status
      error.payload = payload
      throw error
    }

    if (payload && Object.prototype.hasOwnProperty.call(payload, "data")) {
      return payload.data
    }

    return payload
  },

  updateAuthUi(user, xmtpMessage) {
    if (!this.loginButton) {
      return
    }

    this.currentUser = user || null
    if (!user?.id) {
      this.autoJoinAttemptedUsers = new Set()
    }

    if (user) {
      this.loginButton.textContent = `Privy Logout (${this.userLabel(user)})`
      this.loginButton.dataset.privyState = "authed"
    } else {
      this.loginButton.textContent = "Privy Login"
      this.loginButton.dataset.privyState = "ready"
    }

    if (this.xmtpState && typeof xmtpMessage === "string" && xmtpMessage.length > 0) {
      this.xmtpState.textContent = xmtpMessage
    }

    this.updateWatchUi()
  },
}

function cleanText(value, fallback = "") {
  if (typeof value !== "string") {
    return fallback
  }

  const normalized = value.replace(/\s+/g, " ").trim()
  if (normalized.length === 0 || normalized === "null" || normalized === "undefined") {
    return fallback
  }

  return normalized
}

function formatTimestamp(raw) {
  if (!raw) {
    return "-"
  }

  const timestamp = new Date(raw)
  if (Number.isNaN(timestamp.getTime())) {
    return "-"
  }

  return shortDateFormat.format(timestamp)
}

const hooks = {...colocatedHooks, LandingHero}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
