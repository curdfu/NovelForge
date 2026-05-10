import { containsCjk, getFieldDisplayTitle } from '@renderer/utils/fieldDisplay'

export interface SectionConfig {
  title: string
  include?: string[]
  exclude?: string[]
  description?: string
  collapsed?: boolean
}

interface LayoutSources {
  schemaMeta?: Record<string, unknown>
  backendLayout?: SectionConfig[] | undefined
  frontendDefault?: SectionConfig[] | undefined
}

// 简单合并策略：schemaMeta>backend>frontend
export function mergeSections(sources: LayoutSources): SectionConfig[] | undefined {
  if (sources.schemaMeta && Array.isArray(sources.schemaMeta.sections)) {
    return normalizeSections(sources.schemaMeta.sections, sources.schemaMeta)
  }
  if (sources.backendLayout && sources.backendLayout.length) return normalizeSections(sources.backendLayout, sources.schemaMeta)
  if (sources.frontendDefault && sources.frontendDefault.length) return normalizeSections(sources.frontendDefault, sources.schemaMeta)
  return undefined
}

function normalizeSections(sections: unknown[], schemaLike?: Record<string, unknown>): SectionConfig[] {
  return sections.map((s) => {
    const source = asRecord(s)
    return {
      title: normalizeSectionTitle(String(source.title ?? '分区'), source.include, schemaLike),
      include: Array.isArray(source.include) ? source.include.map(String) : undefined,
      exclude: Array.isArray(source.exclude) ? source.exclude.map(String) : undefined,
      description: typeof source.description === 'string' ? source.description : undefined,
      collapsed: !!source.collapsed,
    }
  })
}

function normalizeSectionTitle(rawTitle: string, include: unknown, schemaLike?: Record<string, unknown>): string {
  const title = (rawTitle || '').trim()
  const includeKeys = Array.isArray(include) ? include : []
  if (includeKeys.length !== 1) return title || '分区'

  const key = String(includeKeys[0] || '').trim()
  if (!key) return title || '分区'

  const resolved = resolveSectionTitle(schemaLike, key)
  if (!title || title === key || title.toLowerCase() === key.toLowerCase()) {
    return resolved || key
  }
  return title
}

export function autoGroup(schema: unknown): SectionConfig[] {
  const props = asRecord(asRecord(schema).properties)
  const keys = Object.keys(props)
  const objectKeys = keys.filter(k => resolveType(props[k]) === 'object')
  const arrayKeys = keys.filter(k => resolveType(props[k]) === 'array')
  const scalarKeys = keys.filter(k => !['object','array'].includes(resolveType(props[k])))

  const sections: SectionConfig[] = []
  if (scalarKeys.length) sections.push({ title: '基础信息', include: scalarKeys })
  for (const k of objectKeys) sections.push({ title: resolveSectionTitle(schema, k), include: [k] })
  for (const k of arrayKeys) sections.push({ title: resolveSectionTitle(schema, k), include: [k], collapsed: true })
  return sections
}

function resolveSectionTitle(schema: unknown, key: string): string {
  const fieldSchema = asRecord(asRecord(schema).properties)[key]
  const fieldRecord = asRecord(fieldSchema)
  const directTitle = typeof fieldRecord.title === 'string' ? fieldRecord.title.trim() : ''
  if (containsCjk(directTitle)) return directTitle

  const ref = typeof fieldRecord.$ref === 'string' ? fieldRecord.$ref : ''
  if (ref.startsWith('#/$defs/')) {
    const refName = ref.split('/').pop() || ''
    const refSchema = asRecord(asRecord(asRecord(schema).$defs)[refName])
    const refTitle = typeof refSchema.title === 'string'
      ? refSchema.title.trim()
      : ''
    if (containsCjk(refTitle)) return refTitle
  }

  return getFieldDisplayTitle(key, fieldSchema)
}

function resolveType(s: unknown): string {
  const schema = asRecord(s)
  if (!Object.keys(schema).length) return 'object'
  if (Array.isArray(schema.anyOf)) {
    const first = schema.anyOf.find((x) => {
      const item = asRecord(x)
      return item.type && item.type !== 'null'
    })
    const firstType = asRecord(first).type
    if (typeof firstType === 'string') return firstType
  }
  if (schema.$ref) return 'object'
  return typeof schema.type === 'string' ? schema.type : 'object'
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? (value as Record<string, unknown>) : {}
}
