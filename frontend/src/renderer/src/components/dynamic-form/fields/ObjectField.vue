<template>
  <el-card shadow="never" class="object-field-card">
    <template #header>
      <div class="card-header">
        <span>{{ label }}</span>
      </div>
    </template>
    <ModelDrivenForm
      :schema="effectiveSchema"
      :modelValue="modelValue || {}"
      @update:modelValue="emit('update:modelValue', $event)"
    />
  </el-card>
</template>

<script setup lang="ts">
import { defineAsyncComponent, computed } from 'vue'
import type { JSONSchema } from '@renderer/api/schema'
import { getFieldDisplayTitle } from '@renderer/utils/fieldDisplay'

// 使用前向声明来处理递归组件。
// 这在模块级别打破了循环依赖。
const ModelDrivenForm = defineAsyncComponent(() => import('../ModelDrivenForm.vue'))

const props = defineProps<{
  modelValue: Record<string, unknown> | undefined
  label: string
  schema: JSONSchema
}>()

const emit = defineEmits(['update:modelValue'])

// 当 schema 未声明 properties 但数据存在时，按数据键名动态补齐，保证可渲染
const effectiveSchema = computed<JSONSchema>(() => {
  const sch = props.schema || { type: 'object' }
  const properties = typeof sch === 'object' ? (sch as JSONSchema).properties : undefined
  const hasProps = !!properties && Object.keys(properties).length > 0
  if (hasProps) return sch
  const dataKeys = Object.keys(props.modelValue || {})
  if (dataKeys.length === 0) return sch
  const propsMap: Record<string, JSONSchema> = {}
  for (const k of dataKeys) {
    propsMap[k] = inferSchemaFromValue((props.modelValue || {})[k], k)
  }
  return { ...sch, type: 'object', properties: propsMap }
})

function inferSchemaFromValue(value: unknown, key: string): JSONSchema {
  const title = getFieldDisplayTitle(key)
  if (Array.isArray(value)) {
    const sample = value.find(item => item !== null && item !== undefined)
    return { type: 'array', title, items: inferSchemaFromValue(sample, '项目') }
  }
  if (value && typeof value === 'object') {
    const properties: Record<string, JSONSchema> = {}
    const record = value as Record<string, unknown>
    for (const childKey of Object.keys(record)) {
      properties[childKey] = inferSchemaFromValue(record[childKey], childKey)
    }
    return { type: 'object', title, properties }
  }
  if (typeof value === 'number') return { type: Number.isInteger(value) ? 'integer' : 'number', title }
  if (typeof value === 'boolean') return { type: 'boolean', title }
  return { type: 'string', title }
}
</script>

<style scoped>
.object-field-card {
  margin-top: 10px;
  margin-bottom: 20px;
  background-color: var(--el-fill-color-lighter);
}
</style> 
