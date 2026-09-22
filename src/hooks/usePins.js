import { api } from '../services/api.js';

export const usePins = {
  getAll: async () => {
    const { pins } = await api.listPins({ limit: 500 });
    return pins;
  },

  getClasses: async () => {
    const { pins } = await api.listPins({ limit: 1000 });
    const classSet = new Set();
    pins.forEach(p => { if (p.class) classSet.add(p.class); });
    return Array.from(classSet);
  },

  add: async (pinData) => {
    const { pin } = await api.createPin({
      image: pinData.image,
      thumbnail: pinData.thumbnail,
      title: pinData.title,
      description: pinData.description,
      category: pinData.category,
      class: pinData.class,
      imageWidth: pinData.imageWidth,
      imageHeight: pinData.imageHeight,
      features: pinData.features,
      pose: pinData.pose
    });
    return pin;
  },

  update: async (id, data) => {
    await api.updatePin(id, data);
  },

  delete: async (id) => {
    await api.deletePin(id);
  },

  filter: (pins, searchTerm, filterCategory, selectedClass) => {
    return pins.filter(pin => {
      const matchCat = filterCategory === 'all' || pin.category === filterCategory;
      const matchClass = !selectedClass || pin.class === selectedClass;
      const term = (searchTerm || '').toLowerCase();
      const matchSearch = !term ||
        (pin.title || '').toLowerCase().includes(term) ||
        (pin.description || '').toLowerCase().includes(term) ||
        (pin.category || '').toLowerCase().includes(term) ||
        (pin.class || '').toLowerCase().includes(term);
      return matchCat && matchClass && matchSearch;
    });
  }
};
