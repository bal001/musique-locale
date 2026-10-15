// État d'interface global : notifications (toasts), menu contextuel, boîtes de dialogue.
import { create } from 'zustand';
import type { ReactNode } from 'react';

export interface ElementMenu {
  libelle: string;
  icone?: string;
  action: () => void;
  danger?: boolean;
}

export type Dialogue =
  | { type: 'nouvelle-playlist'; titres?: string[] }
  | { type: 'ajouter-playlist'; titres: string[] }
  | { type: 'modifier-playlist'; id: string }
  | { type: 'raccourcis' }
  | { type: 'confirmer'; message: string; libelle: string; action: () => void };

interface EtatInterface {
  annonce: string;          // texte lu par VoiceOver (région aria-live)
  toasts: { id: number; texte: ReactNode }[];
  menu: { x: number; y: number; elements: ElementMenu[] } | null;
  dialogue: Dialogue | null;
  guideReduit: boolean;
  ouvrirMenu: (x: number, y: number, elements: ElementMenu[]) => void;
  fermerMenu: () => void;
  ouvrirDialogue: (d: Dialogue) => void;
  fermerDialogue: () => void;
  basculerGuide: () => void;
}

let prochainId = 1;

export const useInterface = create<EtatInterface>((set) => ({
  annonce: '',
  toasts: [],
  menu: null,
  dialogue: null,
  guideReduit: false,
  ouvrirMenu: (x, y, elements) => set({ menu: { x, y, elements } }),
  fermerMenu: () => set({ menu: null }),
  ouvrirDialogue: (dialogue) => set({ dialogue, menu: null }),
  fermerDialogue: () => set({ dialogue: null }),
  basculerGuide: () => set((s) => ({ guideReduit: !s.guideReduit })),
}));

// Fait lire un texte par VoiceOver sans rien afficher.
let compteurAnnonce = 0;
export function annoncer(texte: string) {
  // Un caractère invisible alterné force la relecture d'un même texte.
  useInterface.setState({ annonce: texte + (compteurAnnonce++ % 2 ? '\u200b' : '') });
}

export function notifier(texte: ReactNode) {
  const id = prochainId++;
  useInterface.setState((s) => ({ toasts: [...s.toasts.slice(-2), { id, texte }] }));
  setTimeout(() => useInterface.setState((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })), 3500);
}
