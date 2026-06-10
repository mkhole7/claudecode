import React, { useState, useRef } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, ScrollView, StyleSheet,
  Alert, ActivityIndicator, Platform, KeyboardAvoidingView, Modal,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as Calendar from 'expo-calendar';
import { Audio } from 'expo-av';

// ─── Types ────────────────────────────────────────────────────────────────────

type ScheduleType = 'calendar' | 'reminder';
type ReminderCategory = '개인' | '직장' | '쇼핑' | '건강';

interface ParsedItem {
  type: ScheduleType;
  title: string;
  date: Date | null;
  category: ReminderCategory;
  confidence: number;
}

// ─── NLP Parser ───────────────────────────────────────────────────────────────

const CAL_KEYS = ['회의', '미팅', '약속', '세미나', '강의', '수업', '면접', '파티', '행사', '이벤트', '콘서트', '공연', '발표', '출장', '여행', '결혼식', '모임'];
const REM_KEYS = ['잊지마', '기억', '할일', '해야', '반드시', '잊지 마'];
const WORK_KEYS = ['보고서', '제출', '이메일', '업무', '회사', '프로젝트', '마감', '기획서'];
const SHOP_KEYS = ['사야', '구매', '마트', '쇼핑', '장보기', '구입', '살', '사다'];
const HEALTH_KEYS = ['병원', '치과', '한의원', '진료', '운동', '헬스', '조깅', '검진'];
const DAYS: [string, number][] = [['월요일', 1], ['화요일', 2], ['수요일', 3], ['목요일', 4], ['금요일', 5], ['토요일', 6], ['일요일', 0]];

function hasTimeExpr(t: string) { return /\d{1,2}시/.test(t); }

function extractDate(t: string): Date | null {
  const now = new Date();
  let base = new Date(now);
  let hasDate = false, hasTime = false, hour = 9, min = 0;
  const isPM = t.includes('오후') || t.includes('저녁') || t.includes('밤');
  if (t.includes('오늘')) { hasDate = true; }
  else if (t.includes('내일')) { base.setDate(base.getDate() + 1); hasDate = true; }
  else if (t.includes('모레')) { base.setDate(base.getDate() + 2); hasDate = true; }
  const md = t.match(/(\d{1,2})월\s*(\d{1,2})일/);
  if (md) { base = new Date(now.getFullYear(), parseInt(md[1]) - 1, parseInt(md[2])); hasDate = true; }
  const isNext = t.includes('다음주') || t.includes('다음 주');
  for (const [name, wd] of DAYS) {
    if (t.includes(name)) {
      let ahead = wd - now.getDay(); if (ahead <= 0 || isNext) ahead += 7;
      base = new Date(now); base.setDate(base.getDate() + ahead); hasDate = true; break;
    }
  }
  if (t.includes('저녁') && !hasTimeExpr(t)) { hour = 18; hasTime = true; }
  else if (t.includes('아침') && !hasTimeExpr(t)) { hour = 8; hasTime = true; }
  else if (t.includes('점심') && !hasTimeExpr(t)) { hour = 12; hasTime = true; }
  const tm = t.match(/(\d{1,2})시(?:\s*(\d{1,2})분)?/);
  if (tm) {
    hour = parseInt(tm[1]); if (tm[2]) min = parseInt(tm[2]);
    if (isPM && hour < 12) hour += 12;
    if (!isPM && !t.includes('오전') && hour < 9) hour += 12;
    hasTime = true;
  }
  if (!hasDate && !hasTime) return null;
  const d = new Date(base); d.setHours(hasTime ? hour : 9, min, 0, 0); return d;
}

function extractTitle(t: string): string {
  let r = t;
  [/다음\s*주\s*[가-힣]*요일/g, /이번\s*주\s*[가-힣]*요일/g, /[가-힣]*요일/g,
   /\d{1,2}월\s*\d{1,2}일/g, /오늘|내일|모레|글피/g,
   /오전\s*\d{1,2}시(?:\s*\d{1,2}분)?/g, /오후\s*\d{1,2}시(?:\s*\d{1,2}분)?/g,
   /\d{1,2}시\s*\d{1,2}분/g, /\d{1,2}시/g, /오전|오후|저녁|아침|점심|밤/g,
  ].forEach(p => { r = r.replace(p, ''); });
  return r.replace(/\s+/g, ' ').trim() || t;
}

function parseText(t: string): ParsedItem | null {
  t = t.trim(); if (!t) return null;
  const date = extractDate(t), hasTime = hasTimeExpr(t);
  const isCal = CAL_KEYS.some(k => t.includes(k));
  const isRem = [...REM_KEYS, ...SHOP_KEYS].some(k => t.includes(k));
  const type: ScheduleType = isCal ? 'calendar' : isRem ? 'reminder' : hasTime ? 'calendar' : 'reminder';
  const category: ReminderCategory = WORK_KEYS.some(k => t.includes(k)) ? '직장' : SHOP_KEYS.some(k => t.includes(k)) ? '쇼핑' : HEALTH_KEYS.some(k => t.includes(k)) ? '건강' : '개인';
  let conf = 0.4; if (date) conf += 0.3; if (isCal || isRem) conf += 0.2; if (hasTime) conf += 0.1;
  return { type, title: extractTitle(t), date, category, confidence: conf };
}

// ─── Calendar Service ─────────────────────────────────────────────────────────

async function getCalendarId(): Promise<string> {
  const cals = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
  return (cals.find(c => c.allowsModifications) ?? cals[0])?.id ?? '';
}

async function saveToCalendar(item: ParsedItem) {
  const { status } = await Calendar.requestCalendarPermissionsAsync();
  if (status !== 'granted') throw new Error('캘린더 접근 권한이 없습니다.');
  const id = await getCalendarId();
  const start = item.date ?? new Date();
  await Calendar.createEventAsync(id, {
    title: item.title, startDate: start,
    endDate: new Date(start.getTime() + 3600000),
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  });
}

async function saveToReminders(item: ParsedItem) {
  if (Platform.OS !== 'ios') { await saveToCalendar(item); return; }
  const { status } = await Calendar.requestRemindersPermissionsAsync();
  if (status !== 'granted') throw new Error('미리알림 접근 권한이 없습니다.');
  const lists = await Calendar.getCalendarsAsync(Calendar.EntityTypes.REMINDER);
  const list = lists.find(l => l.title === item.category) ?? lists.find(l => l.allowsModifications) ?? lists[0];
  await Calendar.createReminderAsync(list?.id ?? '', { title: item.title, dueDate: item.date ?? undefined, completed: false });
}

// ─── Voice Recording + Whisper ────────────────────────────────────────────────

async function transcribeWithWhisper(uri: string, apiKey: string): Promise<string> {
  const formData = new FormData();
  formData.append('file', { uri, type: 'audio/m4a', name: 'recording.m4a' } as any);
  formData.append('model', 'whisper-1');
  formData.append('language', 'ko');
  const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}` },
    body: formData,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error?.message ?? '음성 인식 실패');
  return data.text ?? '';
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmtDate(d: Date) {
  const dow = ['일', '월', '화', '수', '목', '금', '토'][d.getDay()];
  let h = d.getHours(); const m = String(d.getMinutes()).padStart(2, '0');
  const ap = h >= 12 ? '오후' : '오전'; h = h % 12 || 12;
  return `${d.getMonth() + 1}월 ${d.getDate()}일 (${dow}) ${ap} ${h}:${m}`;
}

const CAT_ICONS: Record<ReminderCategory, string> = { '개인': '👤', '직장': '💼', '쇼핑': '🛒', '건강': '❤️' };
const EXAMPLES = [
  { text: '내일 오후 3시에 팀 미팅', icon: '📅' },
  { text: '다음주 월요일 오전 10시 치과 예약', icon: '📅' },
  { text: '이번 주 금요일까지 보고서 제출', icon: '💼' },
  { text: '마트에서 우유, 계란, 두부 사기', icon: '🛒' },
  { text: '오늘 저녁 6시 헬스장 운동', icon: '🏃' },
];

// ─── Recording Indicator ──────────────────────────────────────────────────────

function PulseCircle() {
  const [scale, setScale] = React.useState(1);
  React.useEffect(() => {
    let up = true;
    const id = setInterval(() => {
      setScale(s => { const next = up ? s + 0.05 : s - 0.05; if (next >= 1.3) up = false; if (next <= 0.8) up = true; return next; });
    }, 50);
    return () => clearInterval(id);
  }, []);
  return <View style={[S.pulseDot, { transform: [{ scale }] }]} />;
}

// ─── App Component ────────────────────────────────────────────────────────────

export default function App() {
  const [input, setInput] = useState('');
  const [item, setItem] = useState<ParsedItem | null>(null);
  const [loading, setLoading] = useState(false);
  const [recording, setRecording] = useState<Audio.Recording | null>(null);
  const [isRecording, setIsRecording] = useState(false);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [apiKey, setApiKey] = useState('');
  const [showSettings, setShowSettings] = useState(false);
  const [apiKeyInput, setApiKeyInput] = useState('');
  const inputRef = useRef<TextInput>(null);

  const onParse = () => { inputRef.current?.blur(); setItem(parseText(input)); };

  const startRecording = async () => {
    const { status } = await Audio.requestPermissionsAsync();
    if (status !== 'granted') { Alert.alert('권한 필요', '마이크 접근 권한이 필요합니다.'); return; }
    await Audio.setAudioModeAsync({ allowsRecordingIOS: true, playsInSilentModeIOS: true });
    const { recording: rec } = await Audio.Recording.createAsync(Audio.RecordingOptionsPresets.HIGH_QUALITY);
    setRecording(rec); setIsRecording(true); setInput('');
  };

  const stopRecording = async () => {
    if (!recording) return;
    setIsRecording(false);
    await recording.stopAndUnloadAsync();
    await Audio.setAudioModeAsync({ allowsRecordingIOS: false });
    const uri = recording.getURI();
    setRecording(null);
    if (!uri) return;

    if (!apiKey) {
      Alert.alert('API 키 필요', 'OpenAI Whisper 음성 인식을 위해 API 키가 필요합니다.', [
        { text: '설정하기', onPress: () => setShowSettings(true) },
        { text: '취소' },
      ]);
      return;
    }
    setIsTranscribing(true);
    try {
      const text = await transcribeWithWhisper(uri, apiKey);
      if (text) { setInput(text); setTimeout(() => setItem(parseText(text)), 300); }
      else { Alert.alert('알림', '음성을 인식하지 못했습니다.'); }
    } catch (e: any) { Alert.alert('오류', e.message); }
    finally { setIsTranscribing(false); }
  };

  const onConfirm = async () => {
    if (!item) return;
    setLoading(true);
    try {
      if (item.type === 'calendar') {
        await saveToCalendar(item);
        Alert.alert('완료 ✓', `'${item.title}'을(를) 캘린더에 추가했어요.`);
      } else {
        await saveToReminders(item);
        Alert.alert('완료 ✓', `'${item.title}'을(를) '${item.category}' 목록에 추가했어요.`);
      }
      setInput(''); setItem(null);
    } catch (e: any) { Alert.alert('오류', e.message ?? '알 수 없는 오류'); }
    finally { setLoading(false); }
  };

  return (
    <KeyboardAvoidingView style={S.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <StatusBar style="dark" />

      {/* Settings Modal */}
      <Modal visible={showSettings} animationType="slide" presentationStyle="pageSheet">
        <View style={S.modalContainer}>
          <View style={S.modalHeader}>
            <Text style={S.modalTitle}>⚙️ OpenAI API 키 설정</Text>
            <TouchableOpacity onPress={() => setShowSettings(false)}>
              <Text style={S.modalClose}>완료</Text>
            </TouchableOpacity>
          </View>
          <Text style={S.modalDesc}>
            음성 녹음을 텍스트로 변환하려면 OpenAI API 키가 필요합니다.{'\n'}
            platform.openai.com에서 발급받으세요.
          </Text>
          <TextInput
            style={S.apiInput}
            placeholder="sk-..."
            value={apiKeyInput}
            onChangeText={setApiKeyInput}
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
          />
          <TouchableOpacity
            style={[S.btn, S.btnBlue, { marginTop: 8 }]}
            onPress={() => { setApiKey(apiKeyInput); setShowSettings(false); }}
          >
            <Text style={S.btnWhiteText}>저장</Text>
          </TouchableOpacity>
        </View>
      </Modal>

      <ScrollView contentContainerStyle={S.scroll} keyboardShouldPersistTaps="handled">
        <View style={S.titleRow}>
          <View>
            <Text style={S.title}>📋 스마트 일정관리</Text>
            <Text style={S.sub}>자연어 · 음성으로 캘린더/미리알림 자동 등록</Text>
          </View>
          <TouchableOpacity onPress={() => { setApiKeyInput(apiKey); setShowSettings(true); }} style={S.settingsBtn}>
            <Text style={S.settingsIcon}>⚙️</Text>
          </TouchableOpacity>
        </View>

        {/* Input Card */}
        <View style={S.card}>
          <Text style={S.cardTitle}>✏️ 일정 입력</Text>

          {isRecording ? (
            <View style={S.recordingBox}>
              <View style={S.recordingRow}>
                <PulseCircle />
                <Text style={S.recordingText}>듣는 중... 말씀해 주세요</Text>
              </View>
              {input ? <Text style={S.interimText}>{input}</Text> : null}
            </View>
          ) : isTranscribing ? (
            <View style={S.recordingBox}>
              <ActivityIndicator size="small" color="#007AFF" />
              <Text style={[S.recordingText, { color: '#007AFF', marginLeft: 8 }]}>음성 변환 중...</Text>
            </View>
          ) : (
            <TextInput
              ref={inputRef}
              style={S.textarea}
              placeholder="텍스트 입력 또는 🎤 버튼으로 음성 입력"
              placeholderTextColor="#999"
              value={input}
              onChangeText={setInput}
              multiline
            />
          )}

          <View style={S.inputActions}>
            <TouchableOpacity
              style={[S.btn, isRecording ? S.btnRed : S.btnMic]}
              onPress={isRecording ? stopRecording : startRecording}
              disabled={isTranscribing}
            >
              <Text style={isRecording ? S.btnWhiteText : S.btnDarkText}>
                {isRecording ? '⏹ 중지' : '🎤 음성 입력'}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[S.btn, S.btnBlue, { flex: 1 }, (!input.trim() || isRecording || isTranscribing) && S.btnGray]}
              onPress={onParse}
              disabled={!input.trim() || isRecording || isTranscribing}
            >
              <Text style={S.btnWhiteText}>✨ 분석하기</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Result Card */}
        {item && (
          <View style={S.card}>
            <View style={S.rowBetween}>
              <Text style={S.cardTitle}>🔍 분석 결과</Text>
              <View style={[S.badge, item.confidence >= 0.8 ? S.badgeGreen : S.badgeOrange]}>
                <Text style={S.badgeText}>{Math.round(item.confidence * 100)}% 확신</Text>
              </View>
            </View>
            <View style={S.hr} />
            <Text style={S.label}>종류</Text>
            <View style={S.seg}>
              {(['calendar', 'reminder'] as ScheduleType[]).map(t => (
                <TouchableOpacity key={t} style={[S.segBtn, item.type === t && S.segBtnOn]}
                  onPress={() => setItem({ ...item, type: t })}>
                  <Text style={[S.segTxt, item.type === t && S.segTxtOn]}>
                    {t === 'calendar' ? '📅 캘린더' : '🔔 미리알림'}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
            <Text style={S.label}>제목</Text>
            <TextInput style={S.titleInput} value={item.title} onChangeText={v => setItem({ ...item, title: v })} />
            <Text style={S.label}>날짜/시간</Text>
            <Text style={S.value}>🕐 {item.date ? fmtDate(item.date) : '날짜 없음'}</Text>
            {item.type === 'reminder' && (
              <>
                <Text style={S.label}>목록</Text>
                <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                  {(['개인', '직장', '쇼핑', '건강'] as ReminderCategory[]).map(cat => (
                    <TouchableOpacity key={cat} style={[S.chip, item.category === cat && S.chipOn]}
                      onPress={() => setItem({ ...item, category: cat })}>
                      <Text style={[S.chipTxt, item.category === cat && S.chipTxtOn]}>{CAT_ICONS[cat]} {cat}</Text>
                    </TouchableOpacity>
                  ))}
                </ScrollView>
              </>
            )}
            <View style={S.hr} />
            <View style={S.rowBetween}>
              <TouchableOpacity style={[S.btn, S.btnLight, { marginRight: 10 }]} onPress={() => setItem(null)}>
                <Text style={S.btnDarkText}>취소</Text>
              </TouchableOpacity>
              <TouchableOpacity style={[S.btn, S.btnBlue, { flex: 1 }]} onPress={onConfirm} disabled={loading}>
                {loading ? <ActivityIndicator color="#fff" />
                  : <Text style={S.btnWhiteText}>{item.type === 'calendar' ? '📅 캘린더에 추가' : '🔔 미리알림에 추가'}</Text>}
              </TouchableOpacity>
            </View>
          </View>
        )}

        {/* Examples */}
        {!item && (
          <View style={S.card}>
            <Text style={S.cardTitle}>💡 예시 (탭하면 입력)</Text>
            {EXAMPLES.map(ex => (
              <TouchableOpacity key={ex.text} style={S.exRow} onPress={() => setInput(ex.text)}>
                <Text style={S.exIcon}>{ex.icon}</Text>
                <Text style={S.exText}>{ex.text}</Text>
                <Text style={S.exArrow}>↖</Text>
              </TouchableOpacity>
            ))}
          </View>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const S = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#F2F2F7' },
  scroll: { padding: 16, paddingTop: 60, paddingBottom: 40 },
  titleRow: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 20 },
  title: { fontSize: 26, fontWeight: '700', color: '#1C1C1E', marginBottom: 4 },
  sub: { fontSize: 14, color: '#6E6E73' },
  settingsBtn: { padding: 4 },
  settingsIcon: { fontSize: 22 },
  card: { backgroundColor: '#fff', borderRadius: 16, padding: 16, marginBottom: 16,
    shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 6, elevation: 2 },
  cardTitle: { fontSize: 16, fontWeight: '600', color: '#1C1C1E', marginBottom: 12 },
  textarea: { minHeight: 90, borderWidth: 1, borderColor: '#E5E5EA', borderRadius: 10,
    padding: 12, fontSize: 15, color: '#1C1C1E', backgroundColor: '#F9F9FB',
    textAlignVertical: 'top', marginBottom: 12 },
  recordingBox: { minHeight: 90, borderWidth: 1, borderColor: '#FFD0D0', borderRadius: 10,
    padding: 12, backgroundColor: '#FFF5F5', marginBottom: 12,
    flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-start' },
  recordingRow: { flexDirection: 'row', alignItems: 'center', width: '100%', marginBottom: 8 },
  recordingText: { fontSize: 15, color: '#FF3B30', fontWeight: '500', marginLeft: 8 },
  interimText: { fontSize: 15, color: '#1C1C1E', width: '100%' },
  pulseDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#FF3B30' },
  inputActions: { flexDirection: 'row', gap: 10 },
  titleInput: { borderWidth: 1, borderColor: '#E5E5EA', borderRadius: 8, padding: 10, fontSize: 15, color: '#1C1C1E', marginBottom: 12 },
  btn: { borderRadius: 12, paddingVertical: 13, paddingHorizontal: 16, alignItems: 'center', justifyContent: 'center' },
  btnBlue: { backgroundColor: '#007AFF' },
  btnRed: { backgroundColor: '#FF3B30' },
  btnMic: { backgroundColor: '#F2F2F7', paddingHorizontal: 16 },
  btnLight: { backgroundColor: '#F2F2F7', paddingHorizontal: 20 },
  btnGray: { backgroundColor: '#C7C7CC' },
  btnWhiteText: { color: '#fff', fontWeight: '600', fontSize: 15 },
  btnDarkText: { color: '#1C1C1E', fontWeight: '600', fontSize: 15 },
  hr: { height: 1, backgroundColor: '#E5E5EA', marginVertical: 12 },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  badge: { borderRadius: 8, paddingHorizontal: 8, paddingVertical: 4 },
  badgeGreen: { backgroundColor: 'rgba(52,199,89,0.15)' },
  badgeOrange: { backgroundColor: 'rgba(255,159,10,0.15)' },
  badgeText: { fontSize: 12, fontWeight: '600', color: '#1C1C1E' },
  label: { fontSize: 12, color: '#8E8E93', fontWeight: '500', marginBottom: 6 },
  value: { fontSize: 15, color: '#1C1C1E', marginBottom: 12 },
  seg: { flexDirection: 'row', backgroundColor: '#F2F2F7', borderRadius: 10, padding: 2, marginBottom: 12 },
  segBtn: { flex: 1, paddingVertical: 8, alignItems: 'center', borderRadius: 8 },
  segBtnOn: { backgroundColor: '#fff', shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 2, elevation: 1 },
  segTxt: { fontSize: 14, color: '#8E8E93' },
  segTxtOn: { color: '#1C1C1E', fontWeight: '600' },
  chip: { backgroundColor: '#F2F2F7', borderRadius: 20, paddingHorizontal: 14, paddingVertical: 7, marginRight: 8 },
  chipOn: { backgroundColor: '#007AFF' },
  chipTxt: { fontSize: 14, color: '#1C1C1E' },
  chipTxtOn: { color: '#fff', fontWeight: '600' },
  exRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#F2F2F7' },
  exIcon: { fontSize: 18, marginRight: 10 },
  exText: { flex: 1, fontSize: 14, color: '#3C3C43' },
  exArrow: { fontSize: 14, color: '#C7C7CC' },
  modalContainer: { flex: 1, padding: 20, paddingTop: 30 },
  modalHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 },
  modalTitle: { fontSize: 18, fontWeight: '700', color: '#1C1C1E' },
  modalClose: { fontSize: 16, color: '#007AFF', fontWeight: '600' },
  modalDesc: { fontSize: 14, color: '#6E6E73', lineHeight: 20, marginBottom: 16 },
  apiInput: { borderWidth: 1, borderColor: '#E5E5EA', borderRadius: 10, padding: 12, fontSize: 15, fontFamily: 'monospace', color: '#1C1C1E' },
});
