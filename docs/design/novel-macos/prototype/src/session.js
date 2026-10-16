export const initialSession = {mode:'normal', hidden:false, presentation:false, running:false, paragraph:0, chapter:3};
export function sessionReducer(s, a) {
  switch (a.type) {
    case 'mode': return s.presentation ? s : {...s, mode:a.mode, hidden:false, running:false};
    case 'toggle': return s.presentation ? s : {...s, hidden:!s.hidden, running:false};
    case 'hide': return {...s, hidden:true, running:false};
    case 'restore': return s.presentation ? s : {...s, hidden:false, running:false};
    case 'presentation': return {...s, presentation:a.value, hidden:true, running:false};
    case 'run': return {...s, running:!s.hidden && !s.presentation && a.value};
    case 'step': return s.hidden || s.presentation ? s : {...s, paragraph:Math.max(0, Math.min(9, s.paragraph+a.delta)), running:a.auto?s.running:false};
    case 'anchor': return {...s, paragraph:a.paragraph, running:false};
    case 'chapter': return {...s, chapter:a.chapter, paragraph:0, running:false};
    default: return s;
  }
}
