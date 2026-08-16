export type Chapter = { name: string; title: string; copy: string; image: string; alt: string };
export type Faq = { question: string; answer: string };
export type LegalSection = { title: string; body: string };
export type LegalPage = { title: string; lede: string; sections: LegalSection[] };
export type SiteConfig = {
  name: string; url: string; tagline: string; headline: [string, string]; lede: string; kicker: string;
  summary: string; status: string; platforms: string[]; themeColor: string; mark: string; socialImage: string;
  tokens: { paper: string; field: string; ink: string; inkSoft: string; inkFaint: string; accent: string; accentDark: string; accentSoft: string; lanternA: string; lanternB: string; lanternC: string; blush: string; inkOnDark: string };
  colorScheme: "light" | "dark";
  hero: { image: string; alt: string; caption: string };
  gallery: { src: string; alt: string }[];
  applicationCategory: string;
  availability: "unreleased" | "testflight" | "app-store";
  appStoreUrl?: string; appStoreId?: string; betaNote: string;
  tension: { statement: string; title: string; copy: string };
  chaptersKicker: string; chaptersTitle: string; chaptersLede: string; chapters: Chapter[];
  fit: { kicker: string; title: string; yes: string; no: string };
  privacy: { kicker: string; title: string; copy: string };
  faqs: Faq[]; founder: { quote: string; credit: string; note: string }; closingTitle: [string, string];
  footerFinePrint: string; capabilities: string[]; boundaries: string[]; lastUpdated: string;
  legal: { privacy: LegalPage; support: LegalPage; terms: LegalPage; accessibility: LegalPage; testflight: LegalPage & { testing: string; notIncluded: string } };
  requiredHomeCopy: string[]; prohibitedClaims: string[];
};

export const site: SiteConfig = {
  name: "Anchor",
  url: "https://anchor.significanthobbies.com",
  tagline: "Park the distraction. Keep the session.",
  headline: ["Park the pull.", "Keep the session."],
  lede: "A focus timer for Mac, iPhone and Apple Watch that files the interruption in one keystroke instead of losing the work.",
  kicker: "Local-first focus.",
  summary: "A local-first focus timer for Mac, iPhone and Apple Watch that parks distractions instead of losing the session, and shows what actually costs you your focus.",
  status: "Invite-only TestFlight and Mac beta preparation",
  platforms: ["iPhone", "Mac", "Apple Watch"],
  themeColor: "#0a0c10",
  mark: "/images/brand/mark.png",
  socialImage: "/images/brand/social.png",
  tokens: {
    paper: "#0a0c10", field: "#141922", ink: "#edf1f7", inkSoft: "#94a0b3", inkFaint: "rgba(255,255,255,0.08)",
    accent: "#3b82f6", accentDark: "#2563eb", accentSoft: "#7dd3fc", lanternA: "#3b82f6", lanternB: "#7dd3fc", lanternC: "#fb7185",
    blush: "#1d2532", inkOnDark: "#edf1f7"
  },
  colorScheme: "dark",
  hero: { image: "/images/screens/session.png", alt: "Anchor session with remaining time and lock-a-distraction", caption: "One goal, one ring, one obvious thing to press when something pulls." },
  gallery: [
    { src: "/images/screens/session.png", alt: "Anchor running a focus session" },
    { src: "/images/screens/resume-capture.png", alt: "Anchor asking what pulled you away" },
    { src: "/images/screens/insights.png", alt: "Anchor insights on focus and interruptions" },
    { src: "/images/screens/mini-timer.png", alt: "Anchor compact timer" }
  ],
  applicationCategory: "ProductivityApplication",
  availability: "unreleased",
  betaNote: "Everything stays on your devices. Not listed on the App Store yet.",
  tension: { statement: "Timers assume starting is the hard part.", title: "The hard part is the Slack ping.", copy: "Anchor files the interruption, names your goal and remaining time, and hands you back the session." },
  chaptersKicker: "One session",
  chaptersTitle: "Keep the thread.",
  chaptersLede: "Start, park, resume, then see what actually cost you the hour.",
  chapters: [
    { name: "Session", title: "Stay with the goal.", copy: "A cobalt ring, a named goal, and one control when something pulls.", image: "/images/screens/session.png", alt: "Anchor session" },
    { name: "Resume", title: "Name what pulled.", copy: "Coming back captures the interruption. “Nothing, just a break” is one key away.", image: "/images/screens/resume-capture.png", alt: "Anchor resume capture" },
    { name: "Insights", title: "See the losses too.", copy: "World-came-to-you versus you-went-to-it. One is settings. The other is habit.", image: "/images/screens/insights.png", alt: "Anchor insights" }
  ],
  fit: { kicker: "An honest fit", title: "A timer that takes interruptions seriously.", yes: "Anchor fits if you already sit down to work and lose the thread to a ping or a tab.", no: "It is not a website blocker, a social productivity feed, or an App Store listing yet." },
  privacy: { kicker: "On your devices", title: "Focus data stays with you.", copy: "Anchor stores sessions locally. Supported signed builds may use private iCloud. There is no Anchor account server." },
  faqs: [
    { question: "Do I need an account?", answer: "No. Sessions live on the device." },
    { question: "Is it on the App Store?", answer: "Not yet. This site will not show Apple’s App Store badge until a live apps.apple.com page exists." },
    { question: "Which devices?", answer: "Mac, iPhone, and Apple Watch. The landing uses real captures from those apps." }
  ],
  founder: { quote: "I wanted the interruption filed before I had agreed to it.", credit: "— Sarthak Agrawal, creator of Anchor", note: "An independent app from Significant Hobbies." },
  closingTitle: ["Park the distraction.", "Finish the hour."],
  footerFinePrint: "A focus timer, not a blocker. © 2026 Sarthak Agrawal.",
  capabilities: ["Session: named goal and remaining time", "Parking: one-keystroke interruption log", "Insights: source of lost focus"],
  boundaries: ["No Anchor account", "No advertising SDK", "Not a website blocker", "Not listed on the App Store yet"],
  lastUpdated: "2026-08-17",
  legal: {
    privacy: { title: "Your sessions stay on your devices.", lede: "Anchor is a local-first focus timer.", sections: [
      { title: "What the app stores", body: "Goals, sessions, and interruption notes in Apple’s app storage. Signed builds may use private iCloud." },
      { title: "What we collect", body: "The developer does not operate an account server for your sessions." },
      { title: "Effective date", body: "Last updated 17 August 2026." }
    ]},
    support: { title: "Support, without a maze.", lede: "How to report a problem in the beta.", sections: [
      { title: "Send feedback", body: "Use TestFlight on iPhone, or email from the support page once a public Mac build exists. Omit private session notes." }
    ]},
    terms: { title: "Simple beta terms.", lede: "Pre-release software for personal evaluation.", sections: [
      { title: "Beta software", body: "Features may change. Keep anything you cannot lose somewhere else." },
      { title: "Changes", body: "Last updated 17 August 2026." }
    ]},
    accessibility: { title: "Access is part of the experience.", lede: "Native Apple accessibility, not a separate mode.", sections: [
      { title: "Current support", body: "VoiceOver, Dynamic Type, and Reduce Motion are tested on the principal flows." }
    ]},
    testflight: { title: "The beta is taking shape.", lede: "We only link to Apple after the enrollment URL is verified.", testing: "Start a session, park a distraction, resume, and open Insights.", notIncluded: "A notarized Mac download and an App Store listing are not ready.", sections: [] }
  },
  requiredHomeCopy: [],
  prohibitedClaims: ["available on the app store"]
};
export const links = {
  home: `${site.url}/`, privacy: `${site.url}/privacy/`, support: `${site.url}/support/`,
  terms: `${site.url}/terms/`, accessibility: `${site.url}/accessibility/`, testflight: `${site.url}/testflight/`
};
