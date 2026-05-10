<template>
  <div class="card-market">
    <CardFilterBar :card-types="cardTypes" :initial-settings="initialDisplaySettings" @change="handleFilterChange" />
    <el-scrollbar>
      <div v-if="viewMode === '卡片'">
        <div v-if="filteredCards.length > 0" class="card-grid" :class="{ compact: density==='紧凑' }">
          <el-card v-for="card in filteredCards" :key="card.id" class="card-item" shadow="hover">
            <template #header>
              <div class="card-header">
                <div class="header-left">
                  <el-tag size="small" effect="plain">{{ card.card_type.name }}</el-tag>
                  <span class="title">{{ card.title }}</span>
                </div>
                <div class="header-right">
                  <el-tooltip content="编辑">
                    <el-button text size="small" @click="onEditCard(card.id)">编辑</el-button>
                  </el-tooltip>
                  <el-popconfirm
                    title="确定要删除这张卡片吗？"
                    confirm-button-text="确定"
                    cancel-button-text="取消"
                    @confirm="onDeleteCard(card.id)"
                  >
                    <template #reference>
                      <el-button text type="danger" size="small">删除</el-button>
                    </template>
                  </el-popconfirm>
                </div>
              </div>
            </template>
            <div class="card-content">
              <p class="meta">创建于: {{ formatDate(card.created_at) }}</p>
            </div>
          </el-card>
        </div>
        <el-empty v-else description="未找到匹配的卡片" />
      </div>

      <div v-else>
        <el-table :data="filteredCards" size="small" border stripe>
          <el-table-column prop="title" label="标题" />
          <el-table-column label="类型" width="140">
            <template #default="{ row }">
              <el-tag size="small">{{ row.card_type.name }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column label="创建时间" width="200">
            <template #default="{ row }">{{ formatDate(row.created_at) }}</template>
          </el-table-column>
          <el-table-column label="操作" width="160">
            <template #default="{ row }">
              <el-button size="small" type="primary" plain @click="onEditCard(row.id)">编辑</el-button>
              <el-popconfirm title="确定删除?" @confirm="onDeleteCard(row.id)">
                <template #reference>
                  <el-button size="small" type="danger" plain>删除</el-button>
                </template>
              </el-popconfirm>
            </template>
          </el-table-column>
        </el-table>
      </div>
    </el-scrollbar>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { useCardStore } from '@renderer/stores/useCardStore'
import { storeToRefs } from 'pinia'
import CardFilterBar from './CardFilterBar.vue'

const emit = defineEmits<{ (e: 'edit-card', id: number): void }>()

const cardStore = useCardStore()
const { cards, cardTypes } = storeToRefs(cardStore)

type SortKey = 'recent'|'title'|'type'
type Density = '舒适'|'紧凑'
type ViewMode = '卡片'|'列表'

interface DisplaySettings {
  sortKey: SortKey
  density: Density
  view: ViewMode
}

const DISPLAY_SETTINGS_KEY = 'novelforge.cardMarket.viewSettings'

const defaultDisplaySettings: DisplaySettings = {
  sortKey: 'recent',
  density: '舒适',
  view: '卡片'
}

function isSortKey(value: unknown): value is SortKey {
  return value === 'recent' || value === 'title' || value === 'type'
}

function isDensity(value: unknown): value is Density {
  return value === '舒适' || value === '紧凑'
}

function isViewMode(value: unknown): value is ViewMode {
  return value === '卡片' || value === '列表'
}

function loadDisplaySettings(): DisplaySettings {
  if (typeof window === 'undefined') return { ...defaultDisplaySettings }
  try {
    const raw = window.localStorage.getItem(DISPLAY_SETTINGS_KEY)
    if (!raw) return { ...defaultDisplaySettings }
    const parsed = JSON.parse(raw) as Partial<DisplaySettings>
    return {
      sortKey: isSortKey(parsed.sortKey) ? parsed.sortKey : defaultDisplaySettings.sortKey,
      density: isDensity(parsed.density) ? parsed.density : defaultDisplaySettings.density,
      view: isViewMode(parsed.view) ? parsed.view : defaultDisplaySettings.view
    }
  } catch {
    return { ...defaultDisplaySettings }
  }
}

function saveDisplaySettings(settings: DisplaySettings) {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.setItem(DISPLAY_SETTINGS_KEY, JSON.stringify(settings))
  } catch { }
}

const initialDisplaySettings = loadDisplaySettings()

const keyword = ref('')
const selectedTypes = ref<number[]>([])
const sortKey = ref<SortKey>(initialDisplaySettings.sortKey)
const density = ref<Density>(initialDisplaySettings.density)
const viewMode = ref<ViewMode>(initialDisplaySettings.view)

const filteredCards = computed(() => {
  let list = [...cards.value]
  if (keyword.value.trim()) {
    const keywords = keyword.value.trim().toLowerCase().split(/\s+/)
    list = list.filter(c => {
      const t = (c.title || '').toLowerCase()
      return keywords.every(k => t.includes(k))
    })
  }
  if (selectedTypes.value.length) {
    const set = new Set(selectedTypes.value)
    list = list.filter(c => set.has(c.card_type_id))
  }
  switch (sortKey.value) {
    case 'title':
      list.sort((a, b) => a.title.localeCompare(b.title)); break
    case 'type':
      list.sort((a, b) => a.card_type.name.localeCompare(b.card_type.name)); break
    default:
      list.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
  }
  return list
})

function handleFilterChange(payload: { keyword: string; types: number[]; sortKey: SortKey; density: Density; view: ViewMode }) {
  keyword.value = payload.keyword
  selectedTypes.value = payload.types
  sortKey.value = payload.sortKey
  density.value = payload.density
  viewMode.value = payload.view
  saveDisplaySettings({ sortKey: payload.sortKey, density: payload.density, view: payload.view })
}

function onEditCard(id: number) { emit('edit-card', id) }
async function onDeleteCard(id: number) { await cardStore.removeCard(id) }
function formatDate(dt: string) { return new Date(dt).toLocaleString() }
</script>

<style scoped>
.card-market { height: 100%; padding: 16px 20px; box-sizing: border-box; display: flex; flex-direction: column; gap: 8px; }
.card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; }
.card-grid.compact { grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; }
.card-item { display: flex; flex-direction: column; }
.card-header { display: flex; justify-content: space-between; align-items: center; gap: 8px; min-width: 0; }
.header-left { display: flex; align-items: center; gap: 8px; min-width: 0; flex: 1; }
.title { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.card-content { flex-grow: 1; color: var(--el-text-color-secondary); font-size: 13px; }
.meta { margin: 0; }
:deep(.header-right) { white-space: nowrap; }
</style> 
