// GENERATED from web/src/components/icons.tsx: the same icon set as the website.
// Regenerate when icons change there. Use WIcon(WI.connect, size: 24, color: ...).
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum WI { calendar, home, refresh, check, lock, qr, callMissed, callOut, callIn, flipCamera, speakerLow, speaker, locate, more, chevronUp, chevronRight, chevronDown, videoOff, video, arrow, micOff, mic, bell, advice, ask, askPlus, back, bookmark, box, business, buyer, camera, cart, checkCircle, clip, clock, close, compliance, connect, consultant, contactCard, deals, digital, edit, export, eye, file, funding, globe, grid, heart, help, imageAdd, info, job, jobWork, link, logout, machinery, mentor, moon, other, partner, phone, pin, plus, refer, repair, reply, repost, rupee, school, search, send, service, share, smile, space, sparkle, sun, supplier, tag, talk, tender, thumbsDown, thumbsUp, tick, tickDouble, trash, truck, update, updates, user, users, views, website }

/// SVG body per icon. {C} = colour, {SW/x} = stroke width divided by x (scaled groups).
const Map<WI, (String, double?)> _body = {
  WI.refresh: (r'<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3" /><path d="M19.5 4.5v4h-4" />', null),
  WI.check: (r'<path d="M5 12.5l4.5 4.5L19 7.5" />', null),
  WI.qr: (r'<rect x="3.5" y="3.5" width="6.5" height="6.5" rx="1.5" /><rect x="14" y="3.5" width="6.5" height="6.5" rx="1.5" /><rect x="3.5" y="14" width="6.5" height="6.5" rx="1.5" /><path d="M14 14h2.5v2.5H14zM18 18h2.5v2.5H18zM14 18.5v2M18.5 14h2" />', null),
  WI.lock: (r'<rect x="5" y="10.5" width="14" height="10" rx="2" /><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" />', null),
  WI.callMissed: (r'<path d="M5.2 4h3l1.4 4-2 1.3a11 11 0 0 0 5.1 5.1l1.3-2 4 1.4v3a2 2 0 0 1-2.2 2A15.8 15.8 0 0 1 3.2 6.2 2 2 0 0 1 5.2 4z" /><path d="M15.5 3.5l5 5M20.5 3.5l-5 5" />', null),
  WI.callOut: (r'<path d="M5.2 4h3l1.4 4-2 1.3a11 11 0 0 0 5.1 5.1l1.3-2 4 1.4v3a2 2 0 0 1-2.2 2A15.8 15.8 0 0 1 3.2 6.2 2 2 0 0 1 5.2 4z" /><path d="M15.5 8.5l5-5M16.8 3.5h3.7v3.7" />', null),
  WI.callIn: (r'<path d="M5.2 4h3l1.4 4-2 1.3a11 11 0 0 0 5.1 5.1l1.3-2 4 1.4v3a2 2 0 0 1-2.2 2A15.8 15.8 0 0 1 3.2 6.2 2 2 0 0 1 5.2 4z" /><path d="M20.5 3.5l-5 5M15.5 4.8v3.7h3.7" />', null),
  WI.flipCamera: (r'<path d="M4.5 8h2.6l1.2-2h7.4l1.2 2h2.6a1.2 1.2 0 0 1 1.2 1.2v8.6a1.2 1.2 0 0 1-1.2 1.2H4.5a1.2 1.2 0 0 1-1.2-1.2V9.2A1.2 1.2 0 0 1 4.5 8z" /><path d="M9.2 12.4a3 3 0 0 1 5.3-1.4M14.8 14a3 3 0 0 1-5.3 1.4M14.6 9.6v1.6H13M9.4 16.8v-1.6H11" />', null),
  WI.speakerLow: (r'<path d="M4 9.5h3.2L12 5.2v13.6l-4.8-4.3H4a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1z" /><path d="M15.5 9a4.2 4.2 0 0 1 0 6" />', null),
  WI.speaker: (r'<path d="M4 9.5h3.2L12 5.2v13.6l-4.8-4.3H4a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1z" /><path d="M15.5 9a4.2 4.2 0 0 1 0 6M18.2 6.4a8 8 0 0 1 0 11.2" />', null),
  WI.locate: (r'<circle cx="12" cy="12" r="6.5" /><circle cx="12" cy="12" r="2" /><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3" />', null),
  WI.more: (r'<path d="M5.5 12h.01M12 12h.01M18.5 12h.01" stroke-width="2.8" />', null),
  WI.chevronUp: (r'<path d="M6 14.5l6-6 6 6" />', null),
  WI.chevronRight: (r'<path d="M9.5 5.5L16 12l-6.5 6.5" />', null),
  WI.chevronDown: (r'<path d="M6 9.5l6 6 6-6" />', null),
  WI.videoOff: (r'<rect x="2.8" y="6.5" width="12.7" height="11" rx="2.6" /><path d="M15.5 10.4l5.7-3.2v9.6l-5.7-3.2" /><path d="M3 3.5l18 17" />', null),
  WI.video: (r'<rect x="2.8" y="6.5" width="12.7" height="11" rx="2.6" /><path d="M15.5 10.4l5.7-3.2v9.6l-5.7-3.2" />', null),
  WI.arrow: (r'<path d="M5 12h14M13 6l6 6-6 6" />', 2.4),
  WI.micOff: (r'<rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5 11a7 7 0 0 0 14 0M12 18v3" /><path d="M4 4l16 16" />', null),
  WI.mic: (r'<rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5 11a7 7 0 0 0 14 0M12 18v3" />', null),
  WI.home: (r'<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8" /><path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />', null),
  WI.bell: (r'<path d="M6 9a6 6 0 1 1 12 0c0 5 2 6.5 2 6.5H4S6 14 6 9z" /><path d="M10 19a2 2 0 0 0 4 0" />', null),
  WI.advice: (r'<path d="M9 17.5h6M10 20.5h4" /> <path d="M12 3.5a6 6 0 0 0-3.6 10.8c.7.6 1.1 1.3 1.1 2.2h5c0-.9.4-1.6 1.1-2.2A6 6 0 0 0 12 3.5z" />', null),
  WI.ask: (r'<g transform="translate(0.5 5.2) scale(0.76)" stroke-width="{SW/0.76}"> <path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12" /> <path d="M11 5.5v-2a1.5 1.5 0 0 1 3 0V12" /> <path d="M14 5.5a1.5 1.5 0 0 1 3 0V12" /> <path d="M17 7.5a1.5 1.5 0 0 1 3 0V16a6 6 0 0 1-6 6h-2.8a6 6 0 0 1-5-2.7l-.2-.3c-.3-.5-1.4-2.4-3.3-5.7a1.5 1.5 0 0 1 .5-2 1.9 1.9 0 0 1 2.3.3L8 14" /> </g> <path d="M19 1.6l1.15 3.1 3.1 1.15-3.1 1.15L19 10.1l-1.15-3.1-3.1-1.15 3.1-1.15z" fill="{C}" stroke-width="1.2" />', null),
  WI.askPlus: (r'<g transform="translate(0.5 5.2) scale(0.76)" stroke-width="{SW/0.76}"> <path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12" /> <path d="M11 5.5v-2a1.5 1.5 0 0 1 3 0V12" /> <path d="M14 5.5a1.5 1.5 0 0 1 3 0V12" /> <path d="M17 7.5a1.5 1.5 0 0 1 3 0V16a6 6 0 0 1-6 6h-2.8a6 6 0 0 1-5-2.7l-.2-.3c-.3-.5-1.4-2.4-3.3-5.7a1.5 1.5 0 0 1 .5-2 1.9 1.9 0 0 1 2.3.3L8 14" /> </g> <path d="M19 1.6l1.15 3.1 3.1 1.15-3.1 1.15L19 10.1l-1.15-3.1-3.1-1.15 3.1-1.15z" fill="{C}" stroke-width="1.2" />', null),
  WI.back: (r'<path d="M14.5 5.5L8 12l6.5 6.5" />', null),
  WI.bookmark: (r'<path d="M7.2 3.8h9.6a1.4 1.4 0 0 1 1.4 1.4v14.6l-6.2-4.3-6.2 4.3V5.2a1.4 1.4 0 0 1 1.4-1.4z" />', null),
  WI.box: (r'<path d="M12 3.5l7.8 4.2v8.6L12 20.5l-7.8-4.2V7.7L12 3.5z" /> <path d="M4.5 7.9L12 12l7.5-4.1M12 12v8.3" />', null),
  WI.business: (r'<rect x="3.5" y="7.5" width="17" height="12" rx="2.5" /> <path d="M9 7.5V6a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 6v1.5" />', null),
  WI.buyer: (r'<circle cx="9.5" cy="8" r="3.2" /> <path d="M3.5 19.5c.5-3.2 2.7-5 6-5 1.2 0 2.2.2 3.1.7" /> <path d="M14.5 15.5h4.2l2 2-3 3-3.2-3.2v-1.8z" />', null),
  WI.camera: (r'<path d="M4.5 8h2.6l1.2-2h7.4l1.2 2h2.6a1.2 1.2 0 0 1 1.2 1.2v8.6a1.2 1.2 0 0 1-1.2 1.2H4.5a1.2 1.2 0 0 1-1.2-1.2V9.2A1.2 1.2 0 0 1 4.5 8z" /> <circle cx="12" cy="13.2" r="3.1" />', null),
  WI.cart: (r'<path d="M3 4.5h2.3l1.7 9.2a1.6 1.6 0 0 0 1.6 1.3h8a1.6 1.6 0 0 0 1.6-1.2l1.3-5.8H6.1" /> <circle cx="9.5" cy="19" r="1.3" /> <circle cx="16.5" cy="19" r="1.3" />', null),
  WI.checkCircle: (r'<circle cx="12" cy="12" r="8.6" /> <path d="M8.2 12.4l2.7 2.7 5-5.6" />', null),
  WI.link: (r'<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.2 1.2" /> <path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.2-1.2" />', null),
  WI.clip: (r'<path d="M18.5 11.5l-6.3 6.3a4.2 4.2 0 0 1-6-6l7-7a2.8 2.8 0 0 1 4 4l-7 7a1.4 1.4 0 0 1-2-2l6.3-6.3" />', null),
  WI.clock: (r'<circle cx="12" cy="12" r="8.6" /> <path d="M12 7.2V12l3.2 2" />', null),
  WI.close: (r'<path d="M6 6l12 12M18 6L6 18" />', null),
  // a person with a tie: Consultant / Advisor
  WI.consultant: (r'<circle cx="12" cy="7.2" r="3.2" /> <path d="M5.5 20c.6-3.8 3.1-6 6.5-6s5.9 2.2 6.5 6" /> <path d="M12 14l-1.1 1.8 1.1 3.7 1.1-3.7z" />', null),
  WI.compliance: (r'<path d="M6.5 3.5h8l4 4v13h-12v-17z" /> <path d="M14.5 3.5v4h4M9.5 14l2 2 3.5-4" />', null),
  WI.connect: (r'<circle cx="8.6" cy="12" r="5" /> <circle cx="15.4" cy="12" r="5" />', null),
  WI.contactCard: (r'<rect x="3" y="5" width="18" height="14" rx="2.6" /> <circle cx="9" cy="10.7" r="2.1" /> <path d="M5.6 16.4c.4-1.5 1.7-2.4 3.4-2.4s3 .9 3.4 2.4M14.6 9.8h3.4M14.6 13h3.4" />', null),
  WI.deals: (r'<circle cx="9" cy="12" r="5.2" /> <circle cx="15" cy="12" r="5.2" />', null),
  WI.digital: (r'<rect x="3.5" y="4.5" width="17" height="12" rx="2" /> <path d="M8 20h8M12 16.5V20M10 8.5 8 10.5l2 2M14 8.5l2 2-2 2" />', null),
  WI.edit: (r'<path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17v3z" /> <path d="M13.5 7.5l3 3" />', null),
  WI.export: (r'<circle cx="11" cy="12" r="7.6" /> <path d="M3.4 12h15.2M11 4.4c2.4 2.2 3.4 4.7 3.4 7.6s-1 5.4-3.4 7.6c-2.4-2.2-3.4-4.7-3.4-7.6s1-5.4 3.4-7.6z" /> <path d="M17.5 4.5h3v3M20.5 4.5l-4 4" />', null),
  WI.calendar: (r'<rect x="3.8" y="5.2" width="16.4" height="14.8" rx="2.6" /> <path d="M3.8 10h16.4M8.2 3.4v3.6M15.8 3.4v3.6" />', null),
  WI.eye: (r'<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" /> <circle cx="12" cy="12" r="3" />', null),
  WI.file: (r'<path d="M14 3H7.5A2.5 2.5 0 0 0 5 5.5v13A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V8l-5-5z" /> <path d="M14 3v5h5M9 13h6M9 17h6" />', null),
  WI.funding: (r'<circle cx="12" cy="12" r="9" /> <path d="M8.8 7.8h6.4M8.8 11h6.4M8.8 7.8c3.6 0 3.6 6 0 6l4.4 3.2" />', null),
  WI.globe: (r'<circle cx="12" cy="12" r="8.6" /> <path d="M3.5 12h17M12 3.4c2.4 2.4 3.5 5.3 3.5 8.6s-1.1 6.2-3.5 8.6c-2.4-2.4-3.5-5.3-3.5-8.6S9.6 5.8 12 3.4z" />', null),
  WI.grid: (r'<rect x="4" y="4" width="6.5" height="6.5" rx="1.8" /> <rect x="13.5" y="4" width="6.5" height="6.5" rx="1.8" /> <rect x="4" y="13.5" width="6.5" height="6.5" rx="1.8" /> <rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.8" />', null),
  WI.heart: (r'<path d="M12 20s-8.2-4.9-8.2-10.7A4.5 4.5 0 0 1 12 6.8a4.5 4.5 0 0 1 8.2 2.5C20.2 15.1 12 20 12 20z" />', null),
  WI.imageAdd: (r'<path d="M13 4.2H7.2A3.4 3.4 0 0 0 3.8 7.6v9.2a3.4 3.4 0 0 0 3.4 3.4h9.6a3.4 3.4 0 0 0 3.4-3.4V11" /> <circle cx="9" cy="10" r="1.6" /> <path d="M4.2 17.6l4.6-4.2 3.4 2.9 2.6-2.3 5 4.2" /> <path d="M18.5 3v5M16 5.5h5" />', null),
  WI.help: (r'<circle cx="12" cy="12" r="8.5" /> <path d="M9.6 9.6a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.1-2.4 3.6" /> <path d="M12 16.9h.01" stroke-width="2.6" />', null),
  WI.info: (r'<circle cx="12" cy="12" r="8.5" /> <path d="M12 11v5.5" /> <path d="M12 7.8h.01" stroke-width="2.6" />', null),
  WI.job: (r'<rect x="3.5" y="7.5" width="17" height="12" rx="2.2" /> <path d="M9 7.5V6a1.8 1.8 0 0 1 1.8-1.8h2.4A1.8 1.8 0 0 1 15 6v1.5M3.5 13h17" />', null),
  WI.jobWork: (r'<path d="M3.5 19.5v-8l5 3v-3l5 3v-3l5 3V6.5h2.5v13h-17.5z" /> <path d="M7 17h.01M11 17h.01M15 17h.01" stroke-width="2.4" />', null),
  WI.logout: (r'<path d="M10 4.5H7a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h3" /> <path d="M15.5 8l4 4-4 4" /> <path d="M19.5 12H9.5" />', null),
  WI.machinery: (r'<circle cx="12" cy="12" r="3" /> <path d="M12 3.5v2.3M12 18.2v2.3M3.5 12h2.3M18.2 12h2.3M6 6l1.7 1.7M16.3 16.3 18 18M18 6l-1.7 1.7M7.7 16.3 6 18" />', null),
  WI.mentor: (r'<circle cx="9" cy="8.5" r="3.2" /> <path d="M3.4 19.5c.5-3.1 2.8-4.9 5.6-4.9 1 0 1.9.2 2.7.6" /> <path d="M14.5 19.5 19 15m0 0h-3.4M19 15v3.4" />', null),
  WI.moon: (r'<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" />', null),
  WI.other: (r'<circle cx="12" cy="12" r="8.6" /> <path d="M8.5 12h.01M12 12h.01M15.5 12h.01" stroke-width="2.6" />', null),
  WI.partner: (r'<circle cx="9" cy="12" r="5.2" /> <circle cx="15" cy="12" r="5.2" />', null),
  WI.phone: (r'<path d="M5.2 4h3l1.4 4-2 1.3a11 11 0 0 0 5.1 5.1l1.3-2 4 1.4v3a2 2 0 0 1-2.2 2A15.8 15.8 0 0 1 3.2 6.2 2 2 0 0 1 5.2 4z" />', null),
  WI.pin: (r'<path d="M12 21s6.6-5.5 6.6-11A6.6 6.6 0 0 0 5.4 10C5.4 15.5 12 21 12 21z" /> <circle cx="12" cy="10" r="2.3" />', null),
  WI.plus: (r'<path d="M12 5v14M5 12h14" />', null),
  WI.refer: (r'<circle cx="10" cy="8" r="3.4" /> <path d="M3.5 19.5c.4-3.4 3.1-5.6 6.5-5.6 1.6 0 3 .5 4.1 1.3" /> <path d="M18 14v6M15 17h6" />', null),
  WI.repair: (r'<path d="M14.5 6.2a4 4 0 0 0 4.6 4.6l-8.7 8.7a2.2 2.2 0 0 1-3.1-3.1l8.7-8.7a4 4 0 0 0-1.5-1.5z" /> <path d="M14.3 6.3a4 4 0 0 1 5.4-1.4l-2.4 2.4 1.4 1.4 2.4-2.4" />', null),
  WI.reply: (r'<path d="M9.5 6L4 11.5 9.5 17" /> <path d="M4 11.5h9a6.5 6.5 0 0 1 6.5 6.5v1" />', null),
  WI.repost: (r'<path d="M4 11V9.5A2.5 2.5 0 0 1 6.5 7H18" /> <path d="M15 4l3 3-3 3" /> <path d="M20 13v1.5a2.5 2.5 0 0 1-2.5 2.5H6" /> <path d="M9 20l-3-3 3-3" />', null),
  WI.rupee: (r'<path d="M7 5.5h10M7 9.5h10M7 5.5h2.5a4 4 0 0 1 0 8H7l8 5.5" />', null),
  WI.school: (r'<path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z" /> <path d="M6.5 11.5v4.2c0 1.2 2.5 2.8 5.5 2.8s5.5-1.6 5.5-2.8v-4.2M21.5 9.5v5" />', null),
  WI.search: (r'<circle cx="11" cy="11" r="6.5" /> <path d="m20 20-4.2-4.2" />', null),
  WI.send: (r'<path d="M21 3.5 10.5 14M21 3.5l-6.5 17-4-6.5-6.5-4 17-6.5z" />', null),
  WI.service: (r'<path d="M14.7 6.3a4 4 0 0 0-5.1 5.1L4 17l3 3 5.6-5.6a4 4 0 0 0 5.1-5.1l-2.6 2.6-2.4-.6-.6-2.4 2.6-2.6z" />', null),
  WI.share: (r'<path d="M12 15V3.5" /> <path d="M7.8 7.6L12 3.4l4.2 4.2" /> <path d="M6 11H5.5A1.5 1.5 0 0 0 4 12.5v6A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5v-6a1.5 1.5 0 0 0-1.5-1.5H18" />', null),
  WI.smile: (r'<circle cx="12" cy="12" r="8.5" /> <path d="M8.5 14a4.2 4.2 0 0 0 7 0" /> <path d="M9.2 9.8h.01M14.8 9.8h.01" stroke-width="2.6" />', null),
  WI.space: (r'<path d="M3.5 10 12 4.5l8.5 5.5v9.5h-17V10z" /> <path d="M8.5 19.5v-5.5h7v5.5M8.5 16.8h7" />', null),
  WI.sparkle: (r'<path d="M12 3.5c.7 4.2 2.3 5.8 6.5 6.5-4.2.7-5.8 2.3-6.5 6.5-.7-4.2-2.3-5.8-6.5-6.5 4.2-.7 5.8-2.3 6.5-6.5z" /> <path d="M18.5 16.5v3M17 18h3" />', null),
  WI.sun: (r'<circle cx="12" cy="12" r="4" /> <path d="M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7" />', null),
  WI.supplier: (r'<path d="M3.5 8.2 12 4l8.5 4.2v7.6L12 20l-8.5-4.2V8.2z" /> <path d="M3.5 8.2 12 12.4l8.5-4.2M12 12.4V20" />', null),
  WI.tag: (r'<path d="M3.5 12.2V4.5a1 1 0 0 1 1-1h7.7a1 1 0 0 1 .7.3l7.3 7.3a1 1 0 0 1 0 1.4l-7.6 7.6a1 1 0 0 1-1.4 0L3.8 12.9a1 1 0 0 1-.3-.7z" /> <circle cx="8.2" cy="8.2" r="1.3" />', null),
  WI.talk: (r'<path d="M4.5 4.5h9a2.5 2.5 0 0 1 2.5 2.5v4.5a2.5 2.5 0 0 1-2.5 2.5H9.2l-3.2 3v-3H4.5A2.5 2.5 0 0 1 2 11.5V7a2.5 2.5 0 0 1 2.5-2.5z" /> <path d="M19 9.2h.5A2.5 2.5 0 0 1 22 11.7v4.5a2.5 2.5 0 0 1-2.5 2.5H18v3l-3.2-3h-3" />', null),
  WI.tender: (r'<path d="M4.5 20.5h15M7 17h10l-1.2-3.5H8.2L7 17z" /> <path d="M12 13.5V9M9 9h6l-1-4.5h-4L9 9z" />', null),
  WI.thumbsDown: (r'<path d="M8 13V4H4.8A1.3 1.3 0 0 0 3.5 5.3v6.4A1.3 1.3 0 0 0 4.8 13H8z" /> <path d="M8 13l3.3 6.2a1.7 1.7 0 0 0 3.2-1.1L13.9 15h4.3a2.2 2.2 0 0 0 2.1-2.8l-1.7-6.4A2.2 2.2 0 0 0 16.5 4.2H8" />', null),
  WI.thumbsUp: (r'<path d="M8 11v9H4.8A1.3 1.3 0 0 1 3.5 18.7v-6.4A1.3 1.3 0 0 1 4.8 11H8z" /> <path d="M8 11l3.3-6.2a1.7 1.7 0 0 1 3.2 1.1L13.9 9h4.3a2.2 2.2 0 0 1 2.1 2.8l-1.7 6.4a2.2 2.2 0 0 1-2.1 1.6H8" />', null),
  WI.tick: (r'<path d="M5 12.5l4.5 4.5L19 7.5" />', 2.2),
  WI.tickDouble: (r'<path d="M2.5 12.5l4.5 4.5L15 8" /><path d="M11 15.5l1.5 1.5L21.5 8" />', 2.2),
  WI.trash: (r'<path d="M4.5 7h15M9.5 7V5.2a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1V7M6.5 7l.8 11.2a1.6 1.6 0 0 0 1.6 1.5h6.2a1.6 1.6 0 0 0 1.6-1.5L17.5 7M10 11v5M14 11v5" />', null),
  WI.truck: (r'<path d="M2.8 6.5h10.4v9.8H2.8zM13.2 9.5h4l3 3.4v3.4h-7" /> <circle cx="7" cy="17.4" r="1.9" /> <circle cx="16.8" cy="17.4" r="1.9" />', null),
  WI.update: (r'<circle cx="12" cy="12" r="8.6" stroke-dasharray="3.2 2.4" /> <path d="M10.4 9l4.4 3-4.4 3z" />', null),
  WI.updates: (r'<g transform="translate(0.4 3.4) scale(0.84)" stroke-width="{SW/0.84}"> <path d="M3.5 10.5v3a1 1 0 0 0 1 1H7l1.4 5h2.6l-1.4-5H10l9 4.2V6.3L10 10.5H4.5a1 1 0 0 0-1 1z" /> <path d="M22 9.8v4.4" /> </g> <path d="M19.6 1.4l.95 2.6 2.6.95-2.6.95-.95 2.6-.95-2.6-2.6-.95 2.6-.95z" fill="{C}" stroke-width="1.1" />', null),
  WI.user: (r'<circle cx="12" cy="8.5" r="3.6" /> <path d="M4.8 20c.6-3.6 3.5-5.8 7.2-5.8s6.6 2.2 7.2 5.8" />', null),
  WI.users: (r'<circle cx="9" cy="8.5" r="3.2" /> <path d="M3.4 19.5c.5-3.1 2.8-4.9 5.6-4.9s5.1 1.8 5.6 4.9" /> <path d="M15.6 5.6a3.1 3.1 0 0 1 0 5.8M17.6 14.9c1.7.7 2.8 2.2 3.1 4.2" />', null),
  // views (as on x.com): three rising bars
  WI.views: (r'<path d="M5 20V12.5M10 20V5.5M15 20v-9.5M20 20V8" />', null),
  WI.website: (r'<path d="M21 12a9 9 0 1 0-9 9" /> <path d="M3.6 9h16.8M3.6 15h8.4" /> <path d="M11.6 3a17 17 0 0 0 0 18" /> <path d="M12.5 3c1.7 2.8 2.5 5.9 2.5 9" /> <path d="M19 22v-6" /> <path d="M22 19l-3-3-3 3" />', null),
};

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The AI sparkle inside Ask / Updates (CSS class `ask-spark`): its path and the centre of its box,
/// which is the transform origin for the pulse and the spin.
const Map<WI, (String, double, double)> _spark = {
  WI.askPlus: ('<path d="M19 1.6l1.15 3.1 3.1 1.15-3.1 1.15L19 10.1l-1.15-3.1-3.1-1.15 3.1-1.15z" fill="{C}" stroke-width="1.2" />', 19, 5.85),
  WI.ask: ('<path d="M19 1.6l1.15 3.1 3.1 1.15-3.1 1.15L19 10.1l-1.15-3.1-3.1-1.15 3.1-1.15z" fill="{C}" stroke-width="1.2" />', 19, 5.85),
  WI.updates: ('<path d="M19.6 1.4l.95 2.6 2.6.95-2.6.95-.95 2.6-.95-2.6-2.6-.95 2.6-.95z" fill="{C}" stroke-width="1.1" />', 19.6, 4.95),
};

String _wrap(String body, Color color, double sw) {
  final c = _hex(color);
  final b = body.replaceAll('{C}', c).replaceAllMapped(RegExp(r'\{SW/([\d.]+)\}'), (m) => (sw / double.parse(m[1]!)).toStringAsFixed(3));
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="$c" stroke-width="$sw" '
      'stroke-linecap="round" stroke-linejoin="round" opacity="${(color.a).toStringAsFixed(3)}">$b</svg>';
}

String wiSvg(WI icon, Color color, double strokeWidth) {
  final (body, fixed) = _body[icon]!;
  return _wrap(body, color, fixed ?? strokeWidth);
}

/// One icon from the WebWeb icon set (24px grid, rounded strokes). [fill] fills the shape (active heart, bookmark).
/// Ask and Updates carry the AI sparkle: it pulses like on the web (1.8 s, scale 1 -> 1.3 -> 1), and spins once
/// (0.8 s, the web's `ai-spin`) whenever [spinKey] changes, e.g. on tap.
class WIcon extends StatefulWidget {
  final WI icon;
  final double size;
  final Color? color;
  final double strokeWidth;
  final bool fill;
  /// keep the sparkle still (e.g. tiny icons in dense lists)
  final bool still;
  final int spinKey;
  const WIcon(this.icon, {super.key, this.size = 24, this.color, this.strokeWidth = 1.5, this.fill = false, this.still = false, this.spinKey = 0});

  @override
  State<WIcon> createState() => _WIconState();
}

class _WIconState extends State<WIcon> with TickerProviderStateMixin {
  AnimationController? _pulse;
  AnimationController? _spin;

  bool get _hasSpark => _spark.containsKey(widget.icon) && !widget.still;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  void _setup() {
    if (_hasSpark) {
      _pulse ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
      _spin ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    } else {
      _pulse?.dispose();
      _spin?.dispose();
      _pulse = _spin = null;
    }
  }

  @override
  void didUpdateWidget(WIcon old) {
    super.didUpdateWidget(old);
    if (old.icon != widget.icon || old.still != widget.still) _setup();
    if (old.spinKey != widget.spinKey && _spin != null) _spin!.forward(from: 0);
  }

  @override
  void dispose() {
    _pulse?.dispose();
    _spin?.dispose();
    super.dispose();
  }

  static const _spinCurve = Cubic(0.34, 1.3, 0.64, 1);

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    final (body, fixed) = _body[widget.icon]!;
    final sw = fixed ?? widget.strokeWidth;
    if (!_hasSpark) {
      var svg = _wrap(body, c, sw);
      if (widget.fill) svg = svg.replaceFirst('fill="none"', 'fill="${_hex(c)}"');
      return SvgPicture.string(svg, width: widget.size, height: widget.size);
    }
    final (spark, cx, cy) = _spark[widget.icon]!;
    final base = SvgPicture.string(_wrap(body.replaceFirst(spark, ''), c, sw), width: widget.size, height: widget.size);
    final star = SvgPicture.string(_wrap(spark, c, sw).replaceFirst('stroke="${_hex(c)}"', 'stroke="${_hex(c)}" fill="${_hex(c)}"'), width: widget.size, height: widget.size);
    final origin = Alignment(cx / 12 - 1, cy / 12 - 1);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(children: [
        base,
        AnimatedBuilder(
          animation: Listenable.merge([_pulse, _spin]),
          builder: (_, child) {
            final spinning = _spin!.isAnimating;
            double scale, turns = 0;
            if (spinning) {
              // ai-spin: 0 -> 400deg and 1.25x at 60 %, settles at 360deg and 1x
              final t = _spin!.value;
              if (t < .6) {
                final k = _spinCurve.transform(t / .6);
                turns = 400 / 360 * k;
                scale = 1 + .25 * k;
              } else {
                final k = _spinCurve.transform((t - .6) / .4);
                turns = (400 - 40 * k) / 360;
                scale = 1.25 - .25 * k;
              }
            } else {
              // ask-pulse: 1 -> 1.3 -> 1, ease-in-out
              final t = _pulse!.value;
              scale = 1 + .3 * Curves.easeInOut.transform(t < .5 ? t * 2 : 2 - t * 2);
            }
            return Transform.rotate(angle: turns * 2 * 3.141592653589793, alignment: origin, child: Transform.scale(scale: scale, alignment: origin, child: child));
          },
          child: star,
        ),
      ]),
    );
  }
}

/// Icon for an ask category value (web category-icon.tsx).
WI categoryIcon(String? category) => switch (category) {
      'job' => WI.job,
      'supplier' => WI.supplier,
      'buyer' => WI.buyer,
      'logistics' => WI.truck,
      'funding' => WI.funding,
      'advice' => WI.advice,
      'mentorship' => WI.mentor,
      'partnership' => WI.partner,
      'machinery' => WI.machinery,
      'space' => WI.space,
      'training' => WI.school,
      'jobwork' => WI.jobWork,
      'compliance' => WI.compliance,
      'consultant' => WI.consultant,
      'export' => WI.export,
      'tender' => WI.tender,
      'digital' => WI.digital,
      'repair' => WI.repair,
      'poll' => WI.views,
      'recommend' => WI.refer,
      'daily' => WI.service,
      'events' => WI.users,
      'rental' => WI.truck,
      'wellness' => WI.smile,
      'printing' => WI.file,
      _ => WI.other,
    };
