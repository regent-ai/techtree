// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

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
const ORB_SLOT_COUNT = 7
const THEME_STORAGE_KEY = "phx:theme"
const EXPLICIT_THEME_KEY = "techtree:theme:explicit"
const shortDateFormat = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
})
const ORB_TONES = [
  "sky",
  "mint",
  "rose",
  "orange",
  "violet",
  "sun",
  "sky",
]

const LandingHero = {
  async mounted() {
    this.seedNodeCache = new Map()
    this.watchedNodeIds = new Set()
    this.visibleNodes = []
    this.allNodes = []
    this.selectedSeed = null
    this.selectedNodeId = null
    this.selectedNode = null
    this.selectedOrbKey = null
    this.trollboxMessages = []
    this.trollboxMembership = "viewer"
    this.trollboxMembershipState = "not_joined"
    this.detailRequestId = 0
    this.searchDebounce = null
    this.pollTimer = null
    this.membershipTimer = null
    this.currentUser = null
    this.autoJoinAttemptedUsers = new Set()
    this.currentView = "room"
    this.userExplicitTheme = window.localStorage.getItem(EXPLICIT_THEME_KEY) === "1"

    this.motionReducedMedia = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.mobileMedia = window.matchMedia("(max-width: 980px)")
    this.reduceMotion = this.motionReducedMedia.matches

    this.boundLogin = () => this.onPrivyClick()
    this.boundJoinFlow = () => this.onTrollboxJoin()
    this.boundSeedClick = (event) => this.onSeedClick(event)
    this.boundSeedOver = (event) => this.onSeedHover(event)
    this.boundSeedOut = (event) => this.onSeedLeave(event)
    this.boundSearchInput = (event) => this.onSearchInput(event)
    this.boundNodeClick = (event) => this.onNodeClick(event)
    this.boundWatchToggle = () => this.onWatchToggle()
    this.boundSend = () => this.onTrollboxSend()
    this.boundThemeToggle = (event) => this.onThemeToggle(event)
    this.boundCopyCurl = () => this.onCopyCurl()
    this.boundReturnToRoom = () => this.setView("room")
    this.boundDrawerHandle = () => this.toggleDrawerFromHandle()
    this.boundDrawerClose = () => this.setChatDrawer(false)
    this.boundDrawerChange = () => this.onDrawerToggle()
    this.boundMediaChange = () => this.applyResponsiveMode()
    this.boundMotionPreference = (event) => {
      this.reduceMotion = event.matches
      this.startAmbientMotion()
    }

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
    this.stageTrack = this.el.querySelector("[data-stage-track]")
    this.returnRoomButton = this.el.querySelector("[data-return-room]")
    this.drawerToggle = this.el.querySelector("#tt-chat-drawer-toggle")
    this.chatHandles = this.el.querySelectorAll("[data-chat-handle]")
    this.chatCloseButton = this.el.querySelector("[data-chat-close]")
    this.humanbox = this.el.querySelector("[data-humanbox]")
    this.themeToggle = this.el.querySelector("#themeToggle")
    this.copyCurlButton = this.el.querySelector("#copyCurl")
    this.curlTarget = this.el.querySelector("[data-curl-target]")
    this.skyTreeGraph = this.el.querySelector("#skyTreeGraph")
    this.skySeed = this.el.querySelector("[data-sky-seed]")
    this.skyTitle = this.el.querySelector("[data-sky-title]")
    this.skySummary = this.el.querySelector("[data-sky-summary]")
    this.treeHints = this.el.querySelector("[data-tree-hints]")
    this.roomZone = this.el.querySelector("[data-view='room']")
    this.skyZone = this.el.querySelector("[data-view='sky']")

    this.loginButton?.addEventListener("click", this.boundLogin)
    this.joinButton?.addEventListener("click", this.boundJoinFlow)
    this.seedRoots?.addEventListener("click", this.boundSeedClick)
    this.seedRoots?.addEventListener("mouseover", this.boundSeedOver)
    this.seedRoots?.addEventListener("focusin", this.boundSeedOver)
    this.seedRoots?.addEventListener("mouseout", this.boundSeedOut)
    this.seedRoots?.addEventListener("focusout", this.boundSeedOut)
    this.nodeSearch?.addEventListener("input", this.boundSearchInput)
    this.nodeList?.addEventListener("click", this.boundNodeClick)
    this.skyTreeGraph?.addEventListener("click", this.boundNodeClick)
    this.watchButton?.addEventListener("click", this.boundWatchToggle)
    this.trollboxSend?.addEventListener("click", this.boundSend)
    this.themeToggle?.addEventListener("change", this.boundThemeToggle)
    this.copyCurlButton?.addEventListener("click", this.boundCopyCurl)
    this.returnRoomButton?.addEventListener("click", this.boundReturnToRoom)
    this.chatHandles?.forEach((handle) => handle.addEventListener("click", this.boundDrawerHandle))
    this.chatCloseButton?.addEventListener("click", this.boundDrawerClose)
    this.drawerToggle?.addEventListener("change", this.boundDrawerChange)
    this.mobileMedia.addEventListener("change", this.boundMediaChange)
    this.motionReducedMedia.addEventListener("change", this.boundMotionPreference)

    document.body.classList.add("tt-no-scroll")

    this.setupThemeControl()
    this.applyResponsiveMode({initial: true})
    this.updateViewA11y("room")
    this.setView("room", {immediate: true})
    this.animateHeroIntro()
    this.startAmbientMotion()

    await this.setupPrivy()
    await Promise.all([this.bootstrapGraph(), this.bootstrapTrollbox()])
    this.startPolling()
    this.onDrawerToggle()
  },

  destroyed() {
    this.loginButton?.removeEventListener("click", this.boundLogin)
    this.joinButton?.removeEventListener("click", this.boundJoinFlow)
    this.seedRoots?.removeEventListener("click", this.boundSeedClick)
    this.seedRoots?.removeEventListener("mouseover", this.boundSeedOver)
    this.seedRoots?.removeEventListener("focusin", this.boundSeedOver)
    this.seedRoots?.removeEventListener("mouseout", this.boundSeedOut)
    this.seedRoots?.removeEventListener("focusout", this.boundSeedOut)
    this.nodeSearch?.removeEventListener("input", this.boundSearchInput)
    this.nodeList?.removeEventListener("click", this.boundNodeClick)
    this.skyTreeGraph?.removeEventListener("click", this.boundNodeClick)
    this.watchButton?.removeEventListener("click", this.boundWatchToggle)
    this.trollboxSend?.removeEventListener("click", this.boundSend)
    this.themeToggle?.removeEventListener("change", this.boundThemeToggle)
    this.copyCurlButton?.removeEventListener("click", this.boundCopyCurl)
    this.returnRoomButton?.removeEventListener("click", this.boundReturnToRoom)
    this.chatHandles?.forEach((handle) => handle.removeEventListener("click", this.boundDrawerHandle))
    this.chatCloseButton?.removeEventListener("click", this.boundDrawerClose)
    this.drawerToggle?.removeEventListener("change", this.boundDrawerChange)
    this.mobileMedia.removeEventListener("change", this.boundMediaChange)
    this.motionReducedMedia.removeEventListener("change", this.boundMotionPreference)

    window.clearTimeout(this.searchDebounce)
    window.clearInterval(this.pollTimer)
    window.clearInterval(this.membershipTimer)
    document.body.classList.remove("tt-no-scroll")
  },

  animateHeroIntro() {
    const enterTargets = this.el.querySelectorAll("[data-animate='enter']")
    if (enterTargets.length === 0) {
      return
    }

    if (this.reduceMotion) {
      enterTargets.forEach((target) => {
        target.style.opacity = "1"
        target.style.transform = "none"
      })
      return
    }

    animate(enterTargets, {
      opacity: [0, 1],
      translateY: [20, 0],
      duration: 720,
      delay: stagger(100, {start: 50}),
      ease: "outCubic",
    })
  },

  startAmbientMotion() {
    if (this.reduceMotion) {
      return
    }

    const hintLines = this.treeHints?.querySelectorAll(".tt-tree-hint-line") || []
    const hintNodes = this.treeHints?.querySelectorAll(".tt-tree-hint-node") || []

    if (hintLines.length > 0) {
      animate(hintLines, {
        opacity: [0.2, 0.55],
        translateY: [0, -6],
        duration: 2600,
        loop: true,
        alternate: true,
        delay: stagger(180),
        ease: "inOutSine",
      })
    }

    if (hintNodes.length > 0) {
      animate(hintNodes, {
        opacity: [0.35, 0.85],
        scale: [0.96, 1.03],
        duration: 2200,
        loop: true,
        alternate: true,
        delay: stagger(140),
        ease: "inOutSine",
      })
    }
  },

  setupThemeControl() {
    const storedTheme = window.localStorage.getItem(THEME_STORAGE_KEY)
    const systemPrefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const initialTheme =
      storedTheme === "light" || storedTheme === "dark"
        ? storedTheme
        : systemPrefersDark
          ? "dark"
          : "light"

    this.applyTheme(initialTheme, {persist: false, explicit: storedTheme === "light" || storedTheme === "dark"})
  },

  onThemeToggle(event) {
    const darkMode = Boolean(event.target?.checked)
    this.applyTheme(darkMode ? "dark" : "light", {persist: true, explicit: true})

    if (!this.reduceMotion && event.target) {
      animate(event.target, {
        scale: [0.9, 1.08, 1],
        duration: 260,
        ease: "outBack",
      })
    }
  },

  applyTheme(theme, options = {}) {
    const persist = options.persist === true
    const explicit = options.explicit === true

    if (theme !== "light" && theme !== "dark") {
      return
    }

    document.documentElement.setAttribute("data-theme", theme)
    if (this.themeToggle) {
      this.themeToggle.checked = theme === "dark"
    }

    if (persist) {
      window.localStorage.setItem(THEME_STORAGE_KEY, theme)
    }

    if (explicit) {
      window.localStorage.setItem(EXPLICIT_THEME_KEY, "1")
      this.userExplicitTheme = true
    }
  },

  applyResponsiveMode(options = {}) {
    const initial = options.initial === true
    const mobile = this.mobileMedia.matches

    this.el.dataset.layout = mobile ? "mobile" : "desktop"

    if (this.drawerToggle && initial) {
      this.drawerToggle.checked = true
    }

    if (!mobile) {
      document.body.classList.add("tt-no-scroll")
    } else {
      document.body.classList.remove("tt-no-scroll")
    }
  },

  toggleDrawerFromHandle() {
    if (!this.drawerToggle) {
      return
    }

    this.setChatDrawer(!this.drawerToggle.checked)
  },

  setChatDrawer(open) {
    if (!this.drawerToggle) {
      return
    }

    const nextState = Boolean(open)
    if (this.drawerToggle.checked === nextState) {
      this.onDrawerToggle()
      return
    }

    this.drawerToggle.checked = nextState
    this.onDrawerToggle()
  },

  onDrawerToggle() {
    if (!this.drawerToggle) {
      return
    }

    const open = this.drawerToggle.checked
    this.el.dataset.chatOpen = open ? "true" : "false"

    if (this.reduceMotion || !this.humanbox) {
      return
    }

    const mobile = this.mobileMedia.matches
    animate(this.humanbox, {
      opacity: open ? [0.72, 1] : [1, 0.88],
      translateX: mobile ? [0, 0] : open ? [40, 0] : [0, 20],
      translateY: mobile ? (open ? [36, 0] : [0, 16]) : [0, 0],
      duration: 260,
      ease: "outCubic",
    })
  },

  setView(view, options = {}) {
    if (!this.stageTrack || (view !== "room" && view !== "sky")) {
      return
    }

    const immediate = options.immediate === true
    if (this.currentView === view && !immediate) {
      return
    }

    const targetTransform = view === "sky" ? "translateY(-100%)" : "translateY(0%)"
    this.currentView = view
    this.el.dataset.stage = view
    this.updateViewA11y(view)

    if (immediate || this.reduceMotion) {
      this.stageTrack.style.transform = targetTransform
      return
    }

    const from = view === "sky" ? ["0%", "-100%"] : ["-100%", "0%"]
    animate(this.stageTrack, {
      translateY: from,
      duration: 720,
      ease: "inOutCubic",
    })
  },

  updateViewA11y(view) {
    const roomActive = view === "room"

    if (this.roomZone) {
      this.roomZone.setAttribute("aria-hidden", String(!roomActive))
      this.roomZone.style.pointerEvents = roomActive ? "auto" : "none"
    }

    if (this.skyZone) {
      this.skyZone.setAttribute("aria-hidden", String(roomActive))
      this.skyZone.style.pointerEvents = roomActive ? "none" : "auto"
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
        this.renderSkyTree([])
        return
      }

      await this.activateSeed(seeds[0], {skipSkyLift: true})
    } catch (error) {
      console.error("Node bootstrap failed", error)
      this.renderSeedRoots([])
      this.renderNodeList([], "Unable to load node graph right now.")
      this.setDetailLoading("Graph API unavailable.")
      this.renderSkyTree([])
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
    this.renderSkyTree(nodes)
    this.renderSkyMeta()

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
    const orbKey = target.getAttribute("data-orb-key")
    if (!seed) {
      return
    }

    this.selectedOrbKey = orbKey

    if (seed === this.selectedSeed) {
      this.highlightSelectedSeedOrb()
      this.setView("sky")
      return
    }

    this.activateSeed(seed)
      .then(() => this.setView("sky"))
      .catch((error) => {
        console.error("Seed activation failed", error)
      })
  },

  onSeedHover(event) {
    if (this.reduceMotion) {
      return
    }

    const target = event.target.closest(".tt-seed-orb")
    if (!target) {
      return
    }

    animate(target, {
      scale: [1, 1.08],
      translateY: [0, -2],
      duration: 220,
      ease: "outQuad",
    })
  },

  onSeedLeave(event) {
    if (this.reduceMotion) {
      return
    }

    const target = event.target.closest(".tt-seed-orb")
    if (!target) {
      return
    }

    animate(target, {
      scale: [1.08, 1],
      translateY: [-2, 0],
      duration: 220,
      ease: "outQuad",
    })
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
      this.renderSkyTree(searchNodes)

      if (searchNodes.length > 0) {
        await this.selectNode(searchNodes[0].id)
      } else {
        this.setDetailLoading("No node details available for that query.")
        this.renderComments([], "No comments found for this search.")
      }
    } catch (error) {
      console.error("Node search failed", error)
      this.renderNodeList([], "Search temporarily unavailable.")
      this.renderSkyTree([])
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
        translateY: [12, 0],
        duration: 320,
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
    const path = cleanText(source.path, "")

    return {
      id: source.id == null ? null : String(source.id),
      parent_id: source.parent_id == null ? null : String(source.parent_id),
      seed: cleanText(source.seed, "Unknown"),
      kind: cleanText(source.kind, "node"),
      title: cleanText(source.title, "Untitled node"),
      summary: cleanText(source.summary, "No summary provided."),
      path,
      depth: Number.isFinite(Number(source.depth))
        ? Number(source.depth)
        : path
          ? Math.max(0, path.split(".").length - 1)
          : 0,
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

  buildSeedSlots(seeds) {
    const uniqueSeeds = Array.from(new Set((seeds || []).filter(Boolean)))

    if (uniqueSeeds.length === 0) {
      return Array.from({length: ORB_SLOT_COUNT}, (_, index) => ({
        seed: `Seed ${index + 1}`,
        tone: ORB_TONES[index % ORB_TONES.length],
        disabled: true,
        orbKey: `empty:${index}`,
      }))
    }

    const filled = [...uniqueSeeds.slice(0, ORB_SLOT_COUNT)]
    let index = 0
    while (filled.length < ORB_SLOT_COUNT) {
      filled.push(uniqueSeeds[index % uniqueSeeds.length])
      index += 1
    }

    return filled.map((seed, slotIndex) => ({
      seed,
      tone: ORB_TONES[slotIndex % ORB_TONES.length],
      disabled: false,
      orbKey: `${seed}:${slotIndex}`,
    }))
  },

  renderSeedRoots(seeds) {
    if (!this.seedRoots) {
      return
    }

    const slots = this.buildSeedSlots(seeds)
    this.seedRoots.replaceChildren()

    slots.forEach((slot) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "tt-seed-orb tooltip"
      button.setAttribute("data-tip", slot.seed)
      button.setAttribute("data-seed", slot.seed)
      button.setAttribute("data-tone", slot.tone)
      button.setAttribute("data-orb-key", slot.orbKey)
      button.setAttribute("data-active", "false")
      button.setAttribute("aria-label", `Select seed ${slot.seed}`)

      if (slot.disabled) {
        button.setAttribute("disabled", "disabled")
      }

      this.seedRoots.append(button)
    })

    if (this.selectedSeed) {
      const hasOrbKey = slots.some((slot) => slot.orbKey === this.selectedOrbKey)
      if (!hasOrbKey) {
        const firstForSeed = slots.find((slot) => slot.seed === this.selectedSeed)
        this.selectedOrbKey = firstForSeed?.orbKey || null
      }
    }

    this.highlightSelectedSeedOrb()

    const seedButtons = this.seedRoots.querySelectorAll(".tt-seed-orb")
    if (seedButtons.length > 0 && !this.reduceMotion) {
      animate(seedButtons, {
        opacity: [0, 1],
        scale: [0.86, 1],
        duration: 420,
        delay: stagger(70),
        ease: "outCubic",
      })

      animate(seedButtons, {
        translateY: [0, -4],
        duration: 2400,
        delay: stagger(130),
        direction: "alternate",
        loop: true,
        ease: "inOutSine",
      })
    }
  },

  highlightSelectedSeedOrb() {
    const orbs = this.seedRoots?.querySelectorAll(".tt-seed-orb") || []
    orbs.forEach((orb) => {
      const sameOrb = this.selectedOrbKey && orb.getAttribute("data-orb-key") === this.selectedOrbKey
      const sameSeed = orb.getAttribute("data-seed") === this.selectedSeed
      const active = this.selectedOrbKey ? sameOrb : sameSeed
      orb.setAttribute("data-active", String(Boolean(active)))
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
      const head = document.createElement("span")
      const title = document.createElement("span")

      button.type = "button"
      button.className = "tt-node-item"
      button.setAttribute("data-node-id", String(node.id))
      button.setAttribute("data-active", String(String(node.id) === String(this.selectedNodeId)))
      button.setAttribute("aria-label", `${node.seed} ${node.kind} ${node.title}`)

      head.className = "tt-node-meta"
      head.textContent = `${node.kind} • ${node.seed}`

      title.className = "tt-node-title"
      title.textContent = node.title

      button.append(head, title)
      item.append(button)
      this.nodeList.append(item)
    })

    const items = this.nodeList.querySelectorAll(".tt-node-item")
    if (items.length > 0) {
      animate(items, {
        opacity: [0, 1],
        translateY: [8, 0],
        duration: 280,
        delay: stagger(28),
        ease: "outQuad",
      })
    }
  },

  renderSkyMeta() {
    if (this.skySeed) {
      this.skySeed.textContent = this.selectedSeed ? `Seed • ${this.selectedSeed}` : "Seed • None"
    }
  },

  renderSkyTree(nodes) {
    if (!this.skyTreeGraph) {
      return
    }

    this.skyTreeGraph.replaceChildren()

    if (!Array.isArray(nodes) || nodes.length === 0) {
      const placeholder = document.createElement("div")
      placeholder.className = "tt-sky-placeholder"
      placeholder.innerHTML = '<span class="loading loading-ring loading-lg"></span><p>No tree nodes available for this view.</p>'
      this.skyTreeGraph.append(placeholder)
      return
    }

    const list = document.createElement("ul")
    list.className = "tt-sky-tree-list"

    const visibleNodes = nodes.slice(0, 48)

    visibleNodes.forEach((node) => {
      const item = document.createElement("li")
      item.className = "tt-sky-node-row"
      item.style.setProperty("--node-depth", String(Math.max(0, Number(node.depth || 0))))

      const button = document.createElement("button")
      button.type = "button"
      button.className = "tt-sky-node"
      button.setAttribute("data-node-id", String(node.id))
      button.setAttribute("data-active", String(String(node.id) === String(this.selectedNodeId)))

      const kindBadge = document.createElement("span")
      kindBadge.className = "badge badge-ghost badge-xs"
      kindBadge.textContent = node.kind

      const titleText = document.createElement("span")
      titleText.textContent = node.title

      button.append(kindBadge, titleText)

      item.append(button)
      list.append(item)
    })

    if (visibleNodes.length > 0 && visibleNodes.length < 7) {
      const ghostCount = 7 - visibleNodes.length
      const seedLabel = this.selectedSeed || visibleNodes[0].seed || "seed"

      Array.from({length: ghostCount}, (_, index) => index).forEach((index) => {
        const row = document.createElement("li")
        row.className = "tt-sky-node-row"
        row.style.setProperty("--node-depth", String((index % 3) + 1))

        const ghost = document.createElement("span")
        ghost.className = "tt-sky-node tt-sky-node-ghost"
        ghost.textContent = `${seedLabel} branch ${index + 1}`
        row.append(ghost)
        list.append(row)
      })
    }

    this.skyTreeGraph.append(list)

    if (!this.reduceMotion) {
      const rows = list.querySelectorAll(".tt-sky-node")
      animate(rows, {
        opacity: [0, 1],
        translateX: [-10, 0],
        duration: 380,
        delay: stagger(24),
        ease: "outQuad",
      })
    }
  },

  highlightSelectedNode() {
    this.nodeList?.querySelectorAll("[data-node-id]").forEach((el) => {
      el.setAttribute("data-active", String(el.getAttribute("data-node-id") === this.selectedNodeId))
    })
    this.skyTreeGraph?.querySelectorAll("[data-node-id]").forEach((el) => {
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

    if (this.skyTitle) {
      this.skyTitle.textContent = node.title
    }
    if (this.skySummary) {
      this.skySummary.textContent = node.summary
    }

    this.updateWatchUi()
    this.highlightSelectedNode()
  },

  setDetailLoading(message) {
    this.detailSeed.textContent = "Seed / kind"
    this.detailTitle.textContent = "Live node detail"
    this.detailSummary.textContent = message
    this.detailChildCount.textContent = "-"
    this.detailCommentCount.textContent = "-"
    this.detailWatcherCount.textContent = "-"
    this.detailUpdated.textContent = "-"

    if (this.skyTitle) {
      this.skyTitle.textContent = "Tree Canopy"
    }
    if (this.skySummary) {
      this.skySummary.textContent = message
    }

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
        translateX: [-8, 0],
        duration: 260,
        delay: stagger(24),
        ease: "outQuad",
      })
    }
  },

  onCopyCurl() {
    const code = this.curlTarget?.querySelector("pre code")
    if (!code?.textContent) {
      return
    }

    const value = code.textContent.trim()
    if (value.length === 0) {
      return
    }

    navigator.clipboard?.writeText(value).then(() => {
      if (!this.copyCurlButton) {
        return
      }

      const previous = this.copyCurlButton.textContent
      this.copyCurlButton.textContent = "Copied"

      if (!this.reduceMotion) {
        animate(this.copyCurlButton, {
          scale: [0.92, 1.07, 1],
          duration: 280,
          ease: "outBack",
        })
      }

      window.setTimeout(() => {
        this.copyCurlButton.textContent = previous || "Copy"
      }, 1400)
    }).catch(() => {
      if (this.copyCurlButton) {
        this.copyCurlButton.textContent = "Copy failed"
        window.setTimeout(() => {
          this.copyCurlButton.textContent = "Copy"
        }, 1400)
      }
    })
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
        delay: stagger(24),
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
      this.trollboxAccess.textContent = `membership: ${membership} | state: ${state}`
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

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

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
