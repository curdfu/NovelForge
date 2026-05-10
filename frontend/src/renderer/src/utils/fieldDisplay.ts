const CJK_RE = /[\u4e00-\u9fff]/

const FIELD_TITLE_ZH_MAP: Record<string, string> = {
  content: '内容',
  theme: '主题',
  audience: '目标读者',
  narrative_person: '叙事人称',
  story_tags: '故事标签',
  affection: '情感关系',
  name: '名称',
  description: '描述',
  special_abilities_thinking: '金手指设计思考',
  special_abilities: '金手指',
  one_sentence_thinking: '一句话梗概思考',
  one_sentence: '一句话梗概',
  overview_thinking: '大纲扩展思考',
  overview: '概述',
  power_structure: '权力结构',
  currency_system: '货币体系',
  background: '背景',
  major_power_camps: '主要势力阵营',
  world_view_thinking: '世界观设计思考',
  world_view: '世界观',
  volume_count: '总卷数',
  character_thinking: '角色设计思考',
  character_cards: '角色卡',
  scene_thinking: '场景设计思考',
  scene_cards: '场景卡',
  organization_thinking: '组织设计思考',
  organization_cards: '组织卡',
  volume_number: '卷号',
  title: '标题',
  main_target: '主线目标',
  branch_line: '辅线',
  new_character_cards: '新增角色卡',
  new_scene_cards: '新增场景卡',
  stage_count: '阶段数量',
  character_action_list: '角色行动列表',
  entity_action_list: '实体行动列表',
  entity_snapshot: '实体状态快照',
  stage_number: '阶段号',
  chapter_number: '章节号',
  entity_list: '实体列表',
  stage_name: '阶段名称',
  reference_chapter: '参考章节范围',
  analysis: '分析',
  chapter_outline_list: '章节大纲列表',
  entity_type: '实体类型',
  life_span: '生命周期',
  role_type: '角色类型',
  born_scene: '出生场景',
  personality: '性格',
  core_drive: '核心驱动力',
  character_arc: '角色弧光',
  influence: '影响力',
  relationship: '关系',
  dynamic_info: '动态信息',
  dynamic_state: '动态状态',
  category: '类别',
  current_state: '当前状态',
  power_or_effect: '能力或效果',
  rule_definition: '规则定义',
  mastery_hint: '掌握线索',
  fact: '事实',
  summary: '总结',
  note: '备注',
  id: 'ID',
  info: '信息',
}

export function containsCjk(text: unknown): boolean {
  return typeof text === 'string' && CJK_RE.test(text)
}

function readStringProp(source: unknown, key: string): string {
  if (!source || typeof source !== 'object') return ''
  const value = (source as Record<string, unknown>)[key]
  return typeof value === 'string' ? value.trim() : ''
}

function deriveTitleFromDescription(description: unknown): string | undefined {
  if (!containsCjk(description)) return undefined
  const desc = String(description).trim()
  const candidate = desc.split(/[，。；;：:（(\n]/, 1)[0]?.trim()
  if (!candidate) return undefined
  return candidate.length > 16 ? candidate.slice(0, 16).trim() : candidate
}

function normalizeKey(key: string): string {
  return key
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .trim()
}

export function getFieldDisplayTitle(fieldName: string, ...schemas: unknown[]): string {
  for (const schema of schemas) {
    const title = readStringProp(schema, 'title')
    if (containsCjk(title)) return title
  }

  const mapped = FIELD_TITLE_ZH_MAP[fieldName]
  if (mapped) return mapped

  for (const schema of schemas) {
    const derived = deriveTitleFromDescription(readStringProp(schema, 'description'))
    if (derived) return derived
  }

  const normalized = normalizeKey(fieldName)
  return normalized ? `字段：${normalized}` : '未命名字段'
}
